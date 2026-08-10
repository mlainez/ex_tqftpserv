# ex_tqftpserv

> ### ⚠️ Very early work — built for a workshop, not for production
>
> Written for the **Goatmire Elixir workshop** on running Nerves on
> Fairphone 3 hardware. It exists for tinkering and teaching.
>
> **Not an actively maintained project** (yet) — no stability
> guarantees, no test coverage, APIs will change without notice.

Tiny Elixir wrapper around Qualcomm's
[`tqftpserv`](https://github.com/linux-msm/tqftpserv) daemon.

Drops `tqftpserv` into your OTP supervision tree under MuonTrap, so
it gets the usual permanent-restart / clean-shutdown behaviour and
its stdout/stderr ends up in the Logger.

```elixir
{:ex_tqftpserv, github: "mlainez/ex_tqftpserv"}
```

```elixir
children = [
  # …
  ExTqftpserv
]
```

## Note: this library does not start udevd

`tqftpserv` itself doesn't need udev — it just opens a QRTR socket
and serves files from `/lib/firmware`. But on a real Qualcomm
platform you almost certainly need udev for *other* reasons (rmtfs
rules, modalias-based autoload of `=m` drivers, board-specific
device permissions, …).

This library deliberately does not spawn its own `udevd`. If your
system needs one, pair `ex_tqftpserv` with
[`:ex_rmtfs`](https://github.com/mlainez/ex_rmtfs) — which does
`udevd` + `udevadm settle` before launching rmtfs — or arrange for
udev some other way at the system layer. There must be exactly one
udevd per system.

Symptom on a system that's missing udev when it shouldn't be:
`tqftpserv` starts fine but the remote processors stay offline,
because the `=m` drivers that own them never got autoloaded from
modalias and they never came up.

Same naming convention as
[`ex_rmtfs`](https://github.com/mlainez/ex_rmtfs) and
[`ex_hexagonrpcd`](https://github.com/mlainez/ex_hexagonrpcd).
