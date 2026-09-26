# ex_tqftpserv

> ### ⚠️ Very early work — built for a workshop, not for production
>
> Written for the **Goatmire Elixir workshop** on running Nerves on Fairphone 3 hardware. There are no stability guarantees and APIs will change without notice.

Supervises Qualcomm's [`tqftpserv`](https://github.com/linux-msm/tqftpserv),
the TFTP-over-QRTR server the remote processors use to read files from the
host (read-only requests from next to the remoteproc firmware in
`/lib/firmware`, read-write requests from `/tmp/tqftpserv`).

```elixir
{:ex_tqftpserv, github: "mlainez/ex_tqftpserv"}
```

Requires `tqftpserv` (v1.1.1, `packages/tqftpserv` in `nerves_system_fp3`)
and a kernel with QRTR.

## Usage

**Nothing starts automatically** (listing `:ex_tqftpserv` in
`extra_applications` does not start the daemon). Add it to your supervision
tree:

```elixir
children = [
  # …
  ExTqftpserv
]
```

It runs `tqftpserv` under MuonTrap in a process registered as
`ExTqftpserv`. stdout and stderr go to Logger at `:info`. A missing binary
or an exiting daemon is logged and retried with exponential backoff, so it
never makes your supervisor crash-loop.

tqftpserv v1.1.1 takes no command-line arguments (its `main` ignores
`argv`), so there is no option for them.

| Option | Default | Description |
|---|---|---|
| `:name` | `ExTqftpserv` | Registered name |
| `:tqftpserv_bin` | `"tqftpserv"` | Executable, looked up on `$PATH` |
| `:tqftpserv_env` | `[]` | Environment, `[{"KEY", "VALUE"}]` |
| `:log_prefix` | `"[tqftpserv] "` | Prefix for log lines |
| `:min_backoff_ms` | `1_000` | First restart delay |
| `:max_backoff_ms` | `60_000` | Maximum restart delay |

## Note: this library does not start udevd

`tqftpserv` itself doesn't need udev. But on the Fairphone 3 kernel QRTR
(`qrtr`, `qrtr-smd`) and the modem remoteproc driver are modules that udev
autoloads from device modaliases, so something has to run `udevd` and
trigger enumeration — typically
[`ex_rmtfs`](https://github.com/mlainez/ex_rmtfs). There must be exactly
one udevd per system, so this library never spawns its own.

Symptom on a system without udev: `tqftpserv` exits with
`failed to open qrtr socket` (QRTR module not loaded), or starts but the
remote processors never come up to talk to it.

## Status

Tested on the host with a fake `tqftpserv`. Not verified on the device
since the switch to the restart/backoff runner.

## Toolchain

Built and tested with Erlang/OTP 29.1.1 and Elixir 1.20.4, matching the official Nerves systems (see `.tool-versions`).

## License

Apache-2.0
