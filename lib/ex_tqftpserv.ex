defmodule ExTqftpserv do
  @moduledoc """
  Supervises the Qualcomm `tqftpserv` daemon.

  `tqftpserv` is the TFTP-over-QRTR server that the remote processors
  (modem MSS, ADSP, …) use to fetch firmware blobs from the host
  filesystem. Once QRTR is up the daemon can be started and left
  running for the life of the system.

  ## udevd is **not** started by this library

  `tqftpserv` itself only needs QRTR and a populated `/lib/firmware`
  — it does not depend on udev. This library therefore does
  **not** start `udevd`, by design.

  In real Qualcomm systems however the *rest* of the platform often
  does need udev:

    * `rmtfs` ships udev rules (`55-modem.rules`, `65-rmtfs.rules`)
      that wire it to the modem QRTR endpoint;
    * any kernel module built as `=m` on your kernel relies on udev
      reading the device `modalias` to autoload it (remoteproc, fastrpc,
      qrtr-smd, …);
    * board-specific rules may set device permissions or symlinks.

  If you need any of the above, run something else that brings udevd
  up — typically [`:ex_rmtfs`](https://github.com/mlainez/ex_rmtfs),
  which starts `udevd` *and* does `udevadm settle` before launching
  rmtfs. There is intentionally only one udevd per system, so this
  library never tries to spawn its own.

  Symptom check on a board where udev is missing: `tqftpserv` will
  start fine but the remote processors will not be able to discover
  it (you'll see them request firmware over QRTR and get no
  response), because the modaliases of their drivers never got
  loaded and they never came online in the first place.

  ## Usage

      children = [
        # …
        ExTqftpserv
      ]

  or with options:

      {ExTqftpserv, tqftpserv_args: ["--verbose"]}

  ## Options

    * `:tqftpserv_args` — argv passed to tqftpserv (default `[]`)
    * `:tqftpserv_env` — extra environment variables (default `[]`)
    * `:tqftpserv_bin` — alternate binary path (default `"tqftpserv"`,
      resolved on `$PATH`)
    * `:log_prefix` — prefix prepended to log lines
      (default `"[tqftpserv] "`)
  """

  @default_bin "tqftpserv"
  @default_prefix "[tqftpserv] "

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    bin = Keyword.get(opts, :tqftpserv_bin, @default_bin)
    args = Keyword.get(opts, :tqftpserv_args, [])
    env = Keyword.get(opts, :tqftpserv_env, [])
    prefix = Keyword.get(opts, :log_prefix, @default_prefix)

    %{
      id: __MODULE__,
      start:
        {MuonTrap.Daemon, :start_link,
         [
           bin,
           args,
           [
             name: __MODULE__,
             log_output: :info,
             log_prefix: prefix,
             env: env
           ]
         ]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end
end
