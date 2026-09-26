defmodule ExTqftpserv.Daemon do
  @moduledoc """
  Runs one OS daemon under `MuonTrap.Daemon` without ever crashing its
  supervisor.

  A plain `MuonTrap.Daemon` child is restarted immediately by its
  supervisor; if the program is missing or keeps exiting, the supervisor
  exceeds its restart intensity, the application stops, and with
  `start_permanent: true` the device reboots. This process avoids that:

    * it waits until the optional `:wait_for` function returns `true`;
    * it checks the executable exists (`System.find_executable/1`) and logs
      a warning instead of starting when it does not;
    * when the daemon exits (with any status, including 0) it is started
      again after an exponential backoff, capped at `:max_backoff_ms`.

  Used by `ExTqftpserv` to run `tqftpserv`.

  ## Options

    * `:command` - (required) program name or absolute path
    * `:args` - argument list (default `[]`)
    * `:env` - environment as `{"KEY", "VALUE"}` tuples (default `[]`)
    * `:name` - registered name for this process (optional)
    * `:id` - child id (default `ExTqftpserv.Daemon`)
    * `:log_prefix` - prefix for the program's log lines (default `"<command>: "`)
    * `:log_output` - Logger level for the program's output (default `:info`)
    * `:wait_for` - 0-arity function; the daemon is only started once it
      returns `true` (default: always ready)
    * `:poll_ms` - how often `:wait_for` is re-checked (default `500`)
    * `:min_backoff_ms` - first retry delay (default `1_000`)
    * `:max_backoff_ms` - maximum retry delay (default `60_000`); a daemon
      that ran for at least this long restarts with `:min_backoff_ms` again
  """

  use GenServer

  require Logger

  @default_min_backoff 1_000
  @default_max_backoff 60_000
  @default_poll 500

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @doc "Starts the runner. See the module documentation for options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Returns the runner's status: `:waiting` (precondition not met yet),
  `:running`, or `:backoff` (not running, retry scheduled), plus the number
  of times the daemon has been started.
  """
  @spec status(GenServer.server()) :: %{
          status: :waiting | :running | :backoff,
          starts: non_neg_integer()
        }
  def status(server) do
    GenServer.call(server, :status)
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    command = Keyword.fetch!(opts, :command)

    state = %{
      command: command,
      args: opts |> Keyword.get(:args, []) |> normalize_args(),
      env: Keyword.get(opts, :env, []),
      log_prefix: Keyword.get(opts, :log_prefix, "#{Path.basename(command)}: "),
      log_output: Keyword.get(opts, :log_output, :info),
      wait_for: Keyword.get(opts, :wait_for, fn -> true end),
      poll: Keyword.get(opts, :poll_ms, @default_poll),
      min_backoff: Keyword.get(opts, :min_backoff_ms, @default_min_backoff),
      max_backoff: Keyword.get(opts, :max_backoff_ms, @default_max_backoff),
      backoff: nil,
      daemon: nil,
      started_at: nil,
      starts: 0,
      status: :waiting,
      warned: MapSet.new()
    }

    {:ok, state, {:continue, :attempt}}
  end

  @impl GenServer
  def handle_continue(:attempt, state), do: {:noreply, attempt(state)}

  @impl GenServer
  def handle_call(:status, _from, state) do
    {:reply, %{status: state.status, starts: state.starts}, state}
  end

  @impl GenServer
  def handle_info(:attempt, %{daemon: nil} = state), do: {:noreply, attempt(state)}
  def handle_info(:attempt, state), do: {:noreply, state}

  def handle_info({:EXIT, pid, reason}, %{daemon: pid} = state) do
    ran_ms = System.monotonic_time(:millisecond) - state.started_at

    Logger.warning(
      "[ExTqftpserv] #{state.command} exited (#{inspect(reason)}) after #{ran_ms} ms; restarting"
    )

    state = if ran_ms >= state.max_backoff, do: %{state | backoff: nil}, else: state
    {:noreply, schedule_retry(%{state | daemon: nil, started_at: nil})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{daemon: pid}) when is_pid(pid) do
    Process.exit(pid, :shutdown)

    receive do
      {:EXIT, ^pid, _} -> :ok
    after
      5_000 -> Process.exit(pid, :kill)
    end
  end

  def terminate(_reason, _state), do: :ok

  defp attempt(state) do
    if ready?(state.wait_for) do
      case System.find_executable(state.command) do
        nil ->
          state
          |> warn_once(:enoent, "#{state.command} not found; will retry")
          |> schedule_retry()

        path ->
          start_daemon(state, path)
      end
    else
      Process.send_after(self(), :attempt, state.poll)
      %{state | status: :waiting}
    end
  end

  defp start_daemon(state, path) do
    muontrap_opts = [
      env: state.env,
      stderr_to_stdout: true,
      log_output: state.log_output,
      log_prefix: state.log_prefix
    ]

    case MuonTrap.Daemon.start_link(path, state.args, muontrap_opts) do
      {:ok, pid} ->
        Logger.info("[ExTqftpserv] started #{path} #{Enum.join(state.args, " ")}")

        %{
          state
          | daemon: pid,
            status: :running,
            started_at: System.monotonic_time(:millisecond),
            starts: state.starts + 1,
            warned: MapSet.new()
        }

      {:error, reason} ->
        Logger.warning("[ExTqftpserv] failed to start #{path}: #{inspect(reason)}")
        schedule_retry(state)
    end
  end

  defp ready?(fun) do
    fun.() == true
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  defp schedule_retry(state) do
    backoff =
      case state.backoff do
        nil -> state.min_backoff
        prev -> min(prev * 2, state.max_backoff)
      end

    Process.send_after(self(), :attempt, backoff)
    %{state | backoff: backoff, status: :backoff}
  end

  defp warn_once(state, key, message) do
    if MapSet.member?(state.warned, key) do
      Logger.debug("[ExTqftpserv] " <> message)
      state
    else
      Logger.warning("[ExTqftpserv] " <> message)
      %{state | warned: MapSet.put(state.warned, key)}
    end
  end

  defp normalize_args(args) when is_binary(args), do: String.split(args)
  defp normalize_args(args) when is_list(args), do: args
end
