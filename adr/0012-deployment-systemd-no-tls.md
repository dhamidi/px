# 0012. Deployment: systemd unit, plain HTTP, no TLS in the app

Status: Accepted

## Context

The demo app runs on a single exe.dev-managed VM, hostname
`cul-de-sac-rocker`. That VM sits behind exe.dev's own HTTPS reverse
proxy, reachable at `https://cul-de-sac-rocker.exe.xyz`. The proxy
already terminates TLS in front of anything running on the VM: it
auto-detects the smallest listening TCP port above 1024 and forwards
traffic there. There is no Dockerfile-based `EXPOSE` convention to lean
on for that discovery, since this is a plain VM rather than a container
image build — the proxy finds the port by probing, not by reading
metadata declared anywhere in this repo.

Separately from how traffic reaches the app, the app itself needs to
keep running. A `swipl` process started by hand from an SSH session dies
with that session, and does not come back after a VM reboot or a crash.
For a demo that is meant to stay reachable, that is not good enough —
the process needs a supervisor that restarts it automatically and
survives independently of any particular terminal.

## Decision

Run the demo app (`swipl apps/adr_site.pl`) under systemd, as the unit
defined in `deploy/prologex.service`. Prefer installing it as a
`systemctl --user` unit if the VM's user session supports one (i.e. user
lingering / a user manager instance is available); fall back to a
`sudo`-installed system-level unit otherwise. Either way the unit is
configured to restart on failure and to start on boot, so the service's
lifecycle does not depend on anyone being logged in.

The app listens on port 8090, bound to localhost only, and speaks plain
HTTP — not HTTPS. This is deliberate, not a corner cut for lack of
effort: TLS is already terminated by the exe.dev proxy in front of the
VM, so having the origin server also negotiate TLS would be redundant
work solving an already-solved problem. The proxy's port
auto-detection is satisfied by the app simply listening above 1024,
which port 8090 does. (The port picked here is 8090, not the more
obvious 8080 — this VM already has other, unrelated services bound to
8080/8081/8082/9999, discovered only once the unit was actually
started and failed to bind; 8090 was free.)

`deploy/run.sh` wraps the actual `swipl` invocation — setting the
working directory so relative paths (`adr/`, `apps/static/`) resolve
correctly, and setting any environment or config the app needs. This
keeps `deploy/prologex.service`'s `ExecStart` a one-liner that just
invokes the script, rather than duplicating invocation details inside
the unit file.

## Consequences

The app is reachable as plain, unencrypted HTTP to anything that can
reach port 8090 directly, bypassing the exe.dev proxy — for example
another process on the same VM, or another host on the VM's private
network if one exists. For this experiment that is an acceptable
trade-off: the only intended path to the app is through the
exe.dev-terminated HTTPS proxy, and the port is bound to localhost.
Before this deployment pattern would be appropriate outside an
exe.dev-proxied VM, it would need revisiting — either by having the app
speak real TLS itself, or by some other guarantee that the plain-HTTP
port is never exposed beyond a trusted boundary.

Relying on systemd for restart-on-crash and start-on-boot decouples the
service's lifecycle from any particular terminal session or SSH
connection, which is the whole reason to use it here instead of running
`swipl` directly in a shell. The `systemctl --user` vs. system-level
fallback means the exact install path depends on what the VM's session
setup supports, but the unit definition and `deploy/run.sh` are the same
either way — only the install command differs.
