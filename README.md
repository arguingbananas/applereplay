# applereplay

What if a 2006 Apple TV could play the Apple II games of the 1980s, with tools
from 2026?¹

applereplay turns an original (first generation) Apple TV into an Apple II
games console. It boots Debian from a USB stick straight into
[linapple](https://github.com/linappleii/linapple), an Apple II emulator,
running [Total Replay](https://github.com/a2-4am/4cade), a collection of
hundreds of Apple II games behind one menu. Plug in a USB keyboard and play,
at full speed, with correct colours and stereo sound over HDMI.

The build is rootless and runs on an ordinary Linux PC. Only writing the USB
stick needs root.

## What you need

- An original Apple TV (2007, 32-bit EFI) on a TV over HDMI, wired Ethernet
  (for SSH; optional for playing) and a USB keyboard.
- A USB stick of 8 GB or more.
- A Linux PC (x86_64) with `mmdebstrap`, `bubblewrap`, `uidmap` and `git`, and
  unprivileged user namespaces enabled. Built and tested on Linux Mint 22
  (Ubuntu 24.04 based); other distributions should work but are untested.
  Writing the stick needs `bmap-tools` and `gdisk`.

## Files you get yourself

These aren't ours to redistribute, so they stay out of the repository. Put them
in `assets/`:

- `assets/atv-boot/boot.efi`: Apple's boot loader, from an Apple TV update
  image. See
  [atv-linux-loader's instructions](https://github.com/DistroHopper39B/atv-linux-loader#gather-and-copy-necessary-files-this-should-be-done-on-linux)
  (download `2Z694-6013-013.dmg`, extract
  `OSBoot/System/Library/CoreServices/boot.efi` with `7z`).
- `assets/atv-boot/System/Library/Extensions/Dummy.kext`: from
  [DummyKext's releases](https://github.com/DistroHopper39B/DummyKext/releases).
- `assets/total-replay.hdv`: the Total Replay hard disk image, from
  [Total Replay's releases](https://github.com/a2-4am/4cade/releases). It
  contains commercial games from the 1980s.

## Build

```
git clone --recurse-submodules <this repository>
cd applereplay
env/bootstrap.sh         # once: a Debian toolchain in env/root (~1 GB)
env/build-cctools.sh     # once: Apple's linker, needed for the boot loader
./build.sh               # ~5 min: out/rootfs.tar, kernel and initramfs
./mkimage.sh             # out/totalreplay.img, ready to write
```

`build.sh` makes an SSH key for you in `out/ssh/` and the box's host keys in
`out/hostkeys/`; both survive rebuilds. Keep `out/` private.

## Write the stick

Check which device the stick is (`lsblk`), then, with `/dev/sdX` replaced:

```
sudo bmaptool copy out/totalreplay.img /dev/sdX
sudo sgdisk -e /dev/sdX
```

This erases the stick. Put it in the Apple TV and power on: the Apple logo,
some boot text, then Total Replay.

## Using the box

- **Play:** type to search Total Replay's menu, Return to start a game, `?` for
  help.
- **SSH:** `ssh -i out/ssh/totalreplay_ed25519 apple@applereplay.local`. User
  `apple` has passwordless sudo, so the key is as good as root: keep it safe.
- **A shell instead of the game:** `sudo touch /etc/totalreplay/no-kiosk` and
  reboot (remove the file to go back).
- **Speed check:** `sudo fps` prints linapple's frames per second (60 is full
  speed) and CPU use.
- **Picture and sound tests** for when something looks or sounds wrong:
  `tools/av-test` (colour screens) and `tools/sound-test` (a voice on each
  channel). Copy them to the box and run them while someone watches the TV.

## How it works

- **Boot:** Apple's `boot.efi` loads
  [atv-linux-loader](https://github.com/DistroHopper39B/atv-linux-loader)
  (`mach_kernel`), which starts Debian 12's i386 kernel with an embedded
  initramfs.
- **Picture:** Linux's nouveau driver is turned off. Whenever it sets a
  display mode, the Apple TV's HDMI chip sends colours the TV misreads, and
  everything turns purple. X draws on the 1280x720 screen Apple's firmware
  sets up instead, with write-combining turned on for that memory
  (`applereplay-fb-wc`).
- **Sound:** the HDMI chip never tells Linux a TV is connected, so Linux
  skips the HDMI audio setup. `applereplay-hdmi-audio` turns it on each time
  audio starts.
- **Speed:** three patches in `patches/` let linapple build on 32-bit, scale
  without per-pixel division, and redraw only the rows that changed. On the
  Apple TV's 1 GHz CPU that's 60 fps with about half the CPU free.
- **Size:** the picture is 980x672, leaving a black border for TVs that
  overscan. It was tuned on a 720p TV that crops about 4%.

`applereplay.md` has the full engineering notes: what was tried, what was
measured and why things are the way they are.

## Working on this with Claude Code

The project was built with [Claude Code](https://claude.com/claude-code), and
it's set up for you to carry on the same way. Open the repository in Claude
Code and it reads `CLAUDE.md`, which loads `applereplay.md`: the hardware
facts, every fix and measurement, the gotchas, and the list of what's next.
Put anything about your own setup (your build machine, your TV, the box's
address) in `CLAUDE.local.md`; Claude Code loads it too, and git ignores it.

## Thanks

applereplay stands on these projects:

- [linapple](https://github.com/linappleii/linapple), the Apple II emulator.
- [Total Replay](https://github.com/a2-4am/4cade) by 4am and qkumba, and the
  authors of every game in it.
- [atv-linux-loader](https://github.com/DistroHopper39B/atv-linux-loader) and
  [DummyKext](https://github.com/DistroHopper39B/DummyKext) by
  DistroHopper39B, which make Linux on the Apple TV possible.
- [Debian](https://www.debian.org), still shipping a 32-bit kernel.

Our fixes to these projects are offered back upstream; `applereplay.md` lists
them.

## License

applereplay's own files are under the [MIT License](LICENSE). The linapple
patches in `patches/` change GPL-2.0 code and are offered under linapple's
GPL-2.0, like the program they become part of. atv-linux-loader (a submodule)
is GPL-2.0, and Total Replay is MIT; the games in it belong to their authors.

---

¹ The entire project — concept, specification, and code — was an original human idea written by an artificial intelligence.
