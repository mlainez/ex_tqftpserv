defmodule ExTqftpservTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  defp eventually(fun, timeout \\ 5_000) do
    cond do
      fun.() ->
        true

      timeout <= 0 ->
        flunk("condition not met in time")

      true ->
        Process.sleep(50)
        eventually(fun, timeout - 50)
    end
  end

  test "starts tqftpserv without arguments under the ExTqftpserv name", %{tmp_dir: dir} do
    bin = Path.join(dir, "tqftpserv")
    File.write!(bin, "#!/bin/sh\necho \"args=[$*]\" >> #{dir}/calls\nexec sleep 1000\n")
    File.chmod!(bin, 0o755)

    start_supervised!({ExTqftpserv, tqftpserv_bin: bin})

    eventually(fn -> File.exists?(Path.join(dir, "calls")) end)
    assert File.read!(Path.join(dir, "calls")) == "args=[]\n"
    assert %{status: :running, starts: 1} = ExTqftpserv.Daemon.status(ExTqftpserv)
  end

  test "stderr is captured", %{tmp_dir: dir} do
    bin = Path.join(dir, "tqftpserv")
    File.write!(bin, "#!/bin/sh\necho 'failed to open qrtr socket' >&2\nexit 1\n")
    File.chmod!(bin, 0o755)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        start_supervised!({ExTqftpserv, tqftpserv_bin: bin, min_backoff_ms: 5_000})
        eventually(fn -> ExTqftpserv.Daemon.status(ExTqftpserv).status == :backoff end)
      end)

    assert log =~ "[tqftpserv] failed to open qrtr socket"
  end

  test "missing binary or exiting daemon doesn't crash the parent", %{tmp_dir: dir} do
    {:ok, sup} =
      Supervisor.start_link(
        [
          {ExTqftpserv,
           tqftpserv_bin: Path.join(dir, "missing"), min_backoff_ms: 10, max_backoff_ms: 20}
        ],
        strategy: :one_for_one,
        max_restarts: 1
      )

    Process.sleep(200)
    assert Process.alive?(sup)
    assert %{starts: 0} = ExTqftpserv.Daemon.status(ExTqftpserv)
    Supervisor.stop(sup)

    bin = Path.join(dir, "exits")
    File.write!(bin, "#!/bin/sh\nexit 0\n")
    File.chmod!(bin, 0o755)

    {:ok, sup} =
      Supervisor.start_link(
        [{ExTqftpserv, tqftpserv_bin: bin, min_backoff_ms: 10, max_backoff_ms: 20}],
        strategy: :one_for_one,
        max_restarts: 1
      )

    eventually(fn -> ExTqftpserv.Daemon.status(ExTqftpserv).starts >= 3 end)
    assert Process.alive?(sup)
    Supervisor.stop(sup)
  end
end
