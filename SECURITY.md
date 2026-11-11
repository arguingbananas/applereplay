# Security

## Reporting a problem

Please report security problems privately, not in a public issue: on this
repository's GitHub page, open the **Security** tab and choose **Report a
vulnerability**. Say what you found, how to reproduce it, and which commit you
built from. This is a hobby project with no promised response time, but
reports are read and answered.

What belongs here: the build scripts, the files in `overlay/`, the services,
the firewall rules and the linapple patches in `patches/`. Problems in
linapple itself, Total Replay, atv-linux-loader or Debian are best reported to
those projects; if you aren't sure, report it here.

## What the box is, and isn't

applereplay builds a games console for a home network. It is not hardened for
a hostile network or for people you don't trust near the box.

- **SSH** accepts keys only, never passwords, never root. `build.sh` makes a
  key for each builder in `out/ssh/`. User `apple` has passwordless sudo, so
  that key is as good as root: keep `out/` private.
- **Don't share a built image.** It contains the box's private SSH host keys
  and accepts your key.
- **Firewall:** the box answers SSH, mDNS (its name, `applereplay.local`) and
  ping, and drops everything else (`overlay/etc/nftables.conf`).
- **Physical access is full access.** The box logs in by itself to run the
  game, and anyone who can reach the USB stick can read or replace it.
- **Updates don't install themselves.** The image is a snapshot of Debian 12
  from the day you built it. To pick up Debian's security fixes, rebuild and
  rewrite the stick, or run `sudo apt update && sudo apt upgrade` on the box
  over SSH. `env/vuln-check` lists the known vulnerabilities in your built
  image that Debian has already fixed.
- **The emulator** runs as the unprivileged user `apple`, and is built without
  its FTP client, so it opens no network connections.
