defmodule ExTqftpserv do
  @moduledoc """
  Supervises the Qualcomm [`tqftpserv`](https://github.com/linux-msm/tqftpserv)
  daemon.

  `tqftpserv` is the TFTP-over-QRTR server that the remote processors
  (modem MSS, ADSP, …) use to read files from the host: read-only requests
  are served from next to the remoteproc firmware under `/lib/firmware`,
  read-write requests from `/tmp/tqftpserv`. Version 1.1.1 takes no
  command-line arguments.

  ## Usage

  This library has no Application that starts the daemon. Add it to your
  own supervision tree:

      children = [
        # …
        ExTqftpserv
      ]

  or with options:

      {ExTqftpserv, log_prefix: "tftp: "}

  The daemon runs under `MuonTrap` in an `ExTqftpserv.Daemon` process
  registered as `ExTqftpserv`. Its stdout and stderr go to Logger at
  `:info`. A missing binary or an exiting daemon is logged and retried with
  exponential backoff; it never makes the parent supervisor crash-loop.

  ## udevd is **not** started by this library

  `tqftpserv` itself only needs QRTR. On the Fairphone 3 kernel QRTR
  (`qrtr`, `qrtr-smd`) and the modem remoteproc driver are modules, which
  are autoloaded by udev from device modaliases. Run something that starts
  `udevd` and triggers enumeration — typically
  [`ex_rmtfs`](https://github.com/mlainez/ex_rmtfs). There must be only one
  udevd per system, so this library never spawns its own.

  ## Options

    * `:name` - registered name (default `ExTqftpserv`)
    * `:tqftpserv_bin` - executable (default `"tqftpserv"`, looked up on `$PATH`)
    * `:tqftpserv_env` - environment as `{"KEY", "VALUE"}` tuples (default `[]`)
    * `:log_prefix` - prefix for log lines (default `"[tqftpserv] "`)
    * `:min_backoff_ms` / `:max_backoff_ms` - restart backoff
      (default `1_000` / `60_000`)
  """

  @default_bin "tqftpserv"
  @default_prefix "[tqftpserv] "

  @doc "Child spec for running tqftpserv. See the module documentation for options."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    ExTqftpserv.Daemon.child_spec(
      [
        id: __MODULE__,
        name: Keyword.get(opts, :name, __MODULE__),
        command: Keyword.get(opts, :tqftpserv_bin, @default_bin),
        args: [],
        env: Keyword.get(opts, :tqftpserv_env, []),
        log_output: :info,
        log_prefix: Keyword.get(opts, :log_prefix, @default_prefix)
      ] ++ Keyword.take(opts, [:min_backoff_ms, :max_backoff_ms])
    )
  end
end
