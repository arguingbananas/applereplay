# applereplay: Apple TV (1st gen) Apple II retro-emulation box, engineering notes

Notes for whoever works on this next, human or Claude Code (CLAUDE.md loads this
file). Anything about one particular build host, TV or account belongs in
CLAUDE.local.md, which is gitignored.

## Goal
Original Apple TV (32-bit EFI, Intel ~1GHz, NVIDIA G72 / GeForce Go 7300) boots Debian 12 (bookworm, i386, Debian kernel `linux-image-686-pae`, currently 6.1.0-54 = upstream 6.1.190) from a USB flash drive via `atv-linux-loader` (`boot.efi` -> fake `mach_kernel` containing kernel+initrd) straight into linapple running Total Replay.

## Making a change
- Work on a branch, not straight on main.
- Builds stay rootless. Root is only for writing the stick (`bmaptool`, `sgdisk`).
- Change the image through the repo (overlay/, hooks/customize.sh, build.sh, mkimage.sh, patches/), never only by hand on the box. A fix tried on the box isn't done until it's in the repo.
- linapple changes: edit out/src/linapple, `env/devroot build` + `install`, measure with `sudo fps`, then save the diff to patches/ before ./build.sh resets the source. Check patches with `-std=c++11`.
- Prefer Debian packages and Debian's kernel. No nouveau, no OpenGL, no mode changes (see Display rules).
- Nothing personal in tracked files: host names, home paths, IPs, email addresses and keys go in CLAUDE.local.md or out/. Nothing from assets/ gets committed.
- Before committing: `tests/run` (plus `TEST_BOX=1 tests/run` if the box was involved), and a test in tests/ for new tooling. If the image changed: `./build.sh` (it must not report unresolved libraries) and `./mkimage.sh`, then check on the box (services, `journalctl -u`, `sudo fps` at 60) and at the TV for picture and sound.
- Keep these notes current: facts learned, gotchas, status; move finished items out of Next; fixes worth sending upstream go under Upstream contributions. Update README.md if its steps changed.

## Hardware and image facts
- Image layout from mkimage.sh: GPT, p1 = 511M FAT `BOOT` (PARTLABEL `boot`, type Apple TV recovery) with boot.efi, mach_kernel, com.apple.Boot.plist, System/Library/Extensions/Dummy.kext; p2 = 6G ext4 `debian-root` (PARTUUID b632a136-1138-4ea8-9ead-c8891c82dcac). The rest of the stick is unused for now.
- Boot partition GPT type must be "Apple TV recovery" `5265636f-7665-11aa-aa11-00306543ecac` (GParted's `atvrecv` flag); root is a normal Linux filesystem partition.
- Kernel Flags: `root=PARTUUID=b632a136-1138-4ea8-9ead-c8891c82dcac ro video=vesafb net.ifnames=0 consoleblank=0 init_on_alloc=0 modprobe.blacklist=nouveau`. The box can edit them itself: `sudo mount /boot/atv`, edit com.apple.Boot.plist, reboot.
- Decision: keep Debian's kernel; consider a self-built one only if needed. Debian names kernels by ABI (6.1.0-54) while the upstream version is 6.1.190; same kernel.
- The Apple TV's IR receiver (Apple Inc.) shows up as a USB device. Wired Ethernet with DHCP; the box announces itself as applereplay.local (avahi).
- Naming: **applereplay** is the project and the Apple TV (hostname `applereplay`, /etc/hosts `127.0.1.1 applereplay`). Things about the Total Replay software keep `totalreplay` names on purpose: totalreplay-kiosk, /etc/totalreplay, /usr/local/lib/totalreplay, out/ssh/totalreplay_ed25519, out/totalreplay.img. mmdebstrap/debootstrap copy the build host's /etc/hostname into the rootfs; always write it in a customize hook (the overlay does).

## Build host
- Any x86_64 Linux with mmdebstrap, bubblewrap and unprivileged user namespaces. Builds are rootless: mmdebstrap `--mode=unshare` (needs a subuid/subgid range).
- If the project lives in a home directory that other users can't enter (mode 750 is common), mmdebstrap's namespace root can't read project files directly. So build.sh copies the keyring to a world-readable temp dir, and gets project files into the rootfs with mmdebstrap's `sync-in`/`upload` special hooks, not `cp` from a shell hook.
- Ubuntu/Mint lack Debian's archive keys: `env/keyring/*.asc` comes from Debian's debian-archive-keyring 2025.1.
- `env/bootstrap.sh` builds the toolchain (Debian trixie amd64) into `env/root`; `env/run <cmd>` runs a command in it via bwrap with the project at /work (you appear as root inside; files stay owned by you). Has clang 19, xxd, autotools, kernel build deps, gdisk, mtools, dosfstools, e2fsprogs 1.47.2 (`mke2fs -d` accepts a tarball), shellcheck 0.10.0 (added later: in an older env/root, `env/run apt-get -o APT::Sandbox::User=root install shellcheck`). It has no SDL2 headers; linapple is built with env/devroot instead (see Performance).
- `env/build-cctools.sh` builds cctools-port `986-ld64-711` into /opt/cross inside env (needed to link mach_kernel).

## Boot loader
- `mach_kernel` comes from github.com/DistroHopper39B/atv-linux-loader (submodule src/atv-linux-loader, pinned at d0b1076): `make KERNEL=vmlinuz INITRAMFS=initrd` with clang + `/opt/cross/bin/i386-apple-darwin8-ld`. It embeds kernel+initrd, so any kernel change means rebuilding mach_kernel.
- boot.efi is Apple's (from Apple TV update 2Z694-6013-013.dmg). Dummy.kext is from DistroHopper39B/DummyKext.
- Same author's ATV1sm bypasses the EFI signature check to boot any EFI OS (possible future GRUB route).
- Kernel options: Debian dropped i386 kernels after bookworm, so the newest packaged one is bookworm-security `linux-image-686-pae` (6.1.190 as of 2026-11-10). A self-built mainline LTS kernel is possible later.

## Lessons from the first attempt
An earlier stick (not built from this repo) never worked; every problem came from how the image was put together, not from the hardware:
1. **linapple was copied in as a bare binary** linking libSDL3, libSDL3_image, libzip and libcurl, none of them installed. build.sh now builds linapple in the image and fails on unresolved libraries.
2. **SDL kmsdrm can't work on this GPU:** it needs GBM+EGL, and the G72's Mesa driver (nv30) is barely maintained. Don't pursue it.
3. **Disk options:** `total-replay.hdv` is a 32 MB hard disk image: use `--hd1`, not `--d1` (floppy). The config flag is `--config`, not `--conf`.
4. **A read-only root that never got an fstab** means no logs, no DHCP leases, no random seed, and likely a systemd-logind crash loop. The overlay ships a real fstab.
5. **Missing drivers:** an initramfs built with `MODULES=dep` inside QEMU had no NIC, usbhid or sound drivers. Install the real kernel package in the image.
6. "Gave up waiting for suspend/resume device" costs about 35s at boot: `RESUME=none` (overlay/etc/initramfs-tools/conf.d/resume).
7. No RTC time ("System time before build time"): systemd-timesyncd is enabled.

## Pipeline (all rootless)
1. `./build.sh` (~5 min) -> `out/rootfs.tar` + `out/boot/{vmlinuz,initrd}`. mmdebstrap unshare; project files go in via sync-in/upload hooks; `hooks/customize.sh` runs inside the chroot (overlay/, kernel, user `apple`, SSH keys, linapple build with patches/, Total Replay, services, tools/fps). Fails if linapple has unresolved libraries.
2. `./mkimage.sh` -> `out/mach_kernel` (atv-linux-loader) and `out/totalreplay.img` + `out/totalreplay.bmap`.
3. Write: `sudo bmaptool copy out/totalreplay.img /dev/sdX` (the only step needing root), then `sudo sgdisk -e /dev/sdX` to move the backup GPT to the end of the stick. Unmount any auto-mounted partitions first. Small changes can be made on the box instead: kernel flags via `sudo mount /boot/atv`.
- Login: `ssh -i out/ssh/totalreplay_ed25519 apple@applereplay.local` (user apple, passwordless sudo). build.sh makes the key once; host keys persist in out/hostkeys, so known_hosts survives rebuilds.
- Kiosk: tty1 autologin -> `totalreplay-kiosk` shows the IP ~3s, then xinit -> `linapple-sdl2 --autoboot --hd1 /var/games/apple2/total-replay.hdv`, logged to the journal as `linapple`. `sudo touch /etc/totalreplay/no-kiosk` to get a plain shell instead. Killing linapple (`pkill -x linapple-sdl2`, not `-f`, which also matches your ssh command) restarts the kiosk, which is how to apply config changes.
- Gotchas found: `sgdisk -q` silently writes nothing (exit 0); don't remove /etc/resolv.conf before apt runs in the chroot; upstream linapple fails a save-state static_assert on i386 (fixed by patches/linapple-i386-snapshot-align.patch); linapple builds as C++11, so check patches with `-std=c++11`; when building on the box, don't pipe `cmake --build` into `tail` (it hides failures).
- Status 2026-11-11: the image boots on the Apple TV: network, SSH, Xorg, USB keyboard and IR receiver all work. Total Replay runs at full speed (60 fps), 980x672 on the firmware's 1280x720 screen, with correct colours and stereo HDMI sound. A stick built from this repo matched the build file for file and played Karateka flawlessly.
- Display rules learned:
  - **No nouveau.** Apple's firmware leaves a 1280x720 framebuffer (efifb) with the HDMI transmitter set up correctly. As soon as nouveau sets any mode (even 1080p), the TV shows black as purple, white as mint, blue as violet: the transmitter sends YCbCr and the TV reads it as RGB (black = Y16/Cb128/Cr128 shown as R128 G16 B128). Confirmed with tools/av-test and a video of the boot (correct until nouveau loads). So: `modprobe.blacklist=nouveau`, X uses fbdev (overlay/etc/X11/xorg.conf.d/20-fbdev.conf, no shadow framebuffer), no mode changes at all, linapple windowed at `Screen factor = 1.75` (980x672). Not 1.875 (1050x720, the full height): the TV this was tuned on overscans 720p by roughly 3-5% (bottom text line cut in half) with no setting to turn it off, so 24 black lines are left above and below. Still 60 fps (4 source rows -> 7).
  - The CPU (Pentium M class) has no usable PAT, and no MTRR covers the framebuffer, so efifb is uncached: 11 fps, Xorg 82% in memcpy. applereplay-fb-wc.service adds a write-combining MTRR over the efifb range from /proc/iomem: 38 fps.
  - Nothing on this box may use OpenGL: Mesa's nouveau_dri.so (nv40) segfaults. xsession sets `SDL_RENDER_DRIVER=software SDL_FRAMEBUFFER_ACCELERATION=0`; the second is needed because SDL2 on X11 otherwise pushes even its software framebuffer through GL.
  - Under nouveau (history): `--fullscreen` switched X to 640x480; `xrandr --scale 0.5x0.5` drew the picture only on the right; 1366x768 windowed at 2x worked but was purple like everything else.
  - Screenshots from the box: `DISPLAY=:0 import -window root` (shows X's framebuffer, not what the TV makes of it; colour and overscan problems only show on the TV itself).
- Performance: emulation itself is <5% of the CPU; the cost is moving pixels. linapple has no frame skip (one emulated frame + one draw per loop), so speed = fps/60. On any box from the image: `sudo fps [seconds]` (tools/fps, installed as /usr/local/bin/fps) prints frames per second and CPU use, using a uprobe on draw_frame_window through tracefs (no perf needed). Frame counts drop briefly while Total Replay loads from disk; that isn't slowness. For profiling, install linux-perf on the box (`perf record -a`, `perf report --sort comm,dso,symbol`). To test a linapple change: edit out/src/linapple, `env/devroot build` (builds inside an unpacked copy of out/rootfs.tar, the box's own i386 system, which x86_64 runs natively: ~23 s full, seconds incremental, byte-identical to the image's binary), `env/devroot install` (copies it to the box and restarts the kiosk), then `sudo fps` on the box. Save the change as a patch (`git -C out/src/linapple diff -- <file> > patches/...`) before ./build.sh, which resets out/src/linapple. `env/devroot init` again after a rebuild (build warns when the devroot is older than out/rootfs.tar). Steps at 2x (under nouveau, before the efifb switch):
  - Upstream: ~15 fps. Per-pixel 64-bit `__divdi3` in VideoStretch, then ~5 copies of a 3.4 MB frame (stretch, memcpy into the SDL texture, SDL software blit, XShmPutImage, nouveau EXA upload into a freshly allocated and zeroed buffer).
  - patches/linapple-stretch-speedup.patch (division-free stepping, exact-2x fast path, repeated rows memcpy'd; output verified byte-identical to upstream): 25.6 fps.
  - nouveau's `NoAccel` (shadow framebuffer; no per-frame buffer allocation): 31 fps.
  - patches/linapple-sdl2-window-surface.patch part 1 (with SDL's software renderer, draw straight into the window surface; no texture, no renderer): 53 fps.
  - Same patch part 2 (only rescale and send the band of rows that changed since the last frame; full repaint once a second): **60 fps, ~45% CPU idle**.
  - Then on efifb: the changed-rows band is widened to whole blocks that scale exactly (8 source rows -> 15 screen rows at 1.875x, 4 -> 7 at 1.75x), so it works at any scale with output identical to a full redraw: **60 fps, ~47% CPU idle**.
  - Worst case: with fbdev's default shadow framebuffer, scenes where much of the screen changes (attract-mode demos) ran at 52-54 fps, Xorg 18-25% CPU copying the shadow. `ShadowFB false` (XShmPutImage writes straight into the write-combined framebuffer): 59-60 fps over the same two minutes of attract mode, Xorg 1-6%. Further ideas if needed: narrow the dirty band to columns too, an exact fast path for the 4->7 vertical step.
  - Still open (found 2026-11-11 by tests/box.sh): full-screen transitions in the attract mode (e.g. Space Kadet's title screen drawn in over the whole screen, every row changing every frame) hold 56-57 fps with ~28% CPU idle and Xorg ~13%. Spare CPU on average but missed frames suggests some frames overrun 16.7 ms and linapple's pacing then loses a frame. Look at FramePacer and at per-frame times (a uprobe on return of draw_frame_window, or timestamps in the trace).
  - `init_on_alloc=0` (mkimage.sh flags) helped less than first thought (nouveau's EXA path asked for zeroed pages explicitly). Harmless; kept.
- Sound: HDMI audio works through applereplay-hdmi-audio.service; stereo confirmed by ear with tools/sound-test (a voice says "Front left"/"Front right" per channel). Cause: the SiI1390 HDA codec never reports presence (pin sense 0, no ELD), and kernel 6.1's patch_hdmi only binds a pin to its PCM with a valid ELD. Unbound, a stream takes the no-pin path (hdmi_pcm_open_no_pin / prepare with pin_idx < 0), which skips the S/PDIF control assign and the channel setup: DIGI_CONVERT_1 stays 0 (digital out off, silence) and CVT_CHAN_COUNT stays 0 (mono, left channel only). The IEC958 mixer switches can't help (spdif->nid is never assigned). The `inv_jack_detect` hint isn't enough either (ELD still invalid). The service watches /proc/asound/card0/pcm3p/sub0/status and, each time a stream opens, sets DIGI_CONVERT_1=0x01 and CVT_CHAN_COUNT=1 with hda-verb (alsa-tools; root, the hwdep needs CAP_SYS_RAWIO). The codec doesn't implement ASP slot mapping (reads back 0). No audio infoframe is sent; TVs play without one. The SiI1390's own I2C isn't on the SMBus (only 0x48 and 0x69 are there); it hangs off the GPU's I2C.

## Tests
- `tests/run [name...]` runs tests/NAME.sh files (helpers in tests/lib.sh: `check "what" cmd...`, `skip`, `box cmd...` for ssh to the box). Scratch space is out/test. Tests that touch the Apple TV run only with `TEST_BOX=1` (`TEST_HOST` overrides apple@applereplay.local); then an unreachable box is a failure, not a skip, within ~10 s, and ssh gives up ~15 s after a box stops answering.
- tests/static.sh: scripts parse and shellcheck finds no warnings (env/root's shellcheck, else the host's, else skipped: newer versions add warnings, so use env's), services' ExecStart files exist, linapple is at the pinned commit, patches apply in order, out/src/linapple has no unsaved edits, git ignores keys/assets/personal notes, no private keys, home paths, private IPs or personal email addresses tracked. Under a second.
- tests/image.sh: out/rootfs.tar is newer than every build input (else rebuild), then hostname, X/fbdev config, linapple config, default sound device, enabled services, masked apt timers, SSH settings, authorized key, installed programs, kernel, kernel flags, partition types and UUIDs, boot partition contents, bmap. A few seconds.
- tests/stretch.sh: tests/stretch-harness.cpp built against upstream's and the patched VideoStretch.cpp (604 cases: every function and pixel format, the Apple TV's scales, random sizes, offsets and clipping) must give identical pixels, on x86_64 and, with a devroot, on i386; and bands of whole row blocks must match the full frame at 768/720/672 lines (what the changed-rows drawing relies on). ~40 s. Gotcha: `git apply` inside a directory that sits within this repo silently applies nothing; the test gives its scratch trees their own `git init`.
- tests/box.sh (TEST_BOX=1): hostname, nouveau off and efifb, services up and none failed, write-combining MTRR, linapple running with ShadowFB off, HDMI stream with digital out and 2 channels, and `sudo fps 20` >= 55.
- tests/devroot.sh: init (i386, Debian 12, uname i686), build (32-bit, byte-identical to the image's linapple-sdl2), incremental rebuilds (0 files, then exactly 1), the stale-devroot warning, the rm -rf guard, usage; with TEST_BOX=1, install on the box. ~35 s.

## Next
- Compute `Screen factor` at startup instead of hard-coding 1.75. xsession reads the real screen size (the firmware picks the mode; 1280x720 here, not confirmed for other TVs) and uses the largest factor that fits with an overscan margin of about 7% (1.75 at 720 lines), with an override in /etc/totalreplay for unusual TVs.
- Then: Apple Remote (hid-appleir), verify.sh, grow root partition, quiet boot, read-only root, or a lighter emulator.
- Minor: replace the grey Apple logo at boot with an original applereplay logo whose theme is 2026 technology driving 2006 hardware to emulate 1980s Apple II games. For example: Apple II hi-res colours and pixel lettering, the Apple TV's case outline, a modern touch, and the tagline "2026 tech · 2006 hardware · 1980s games". Don't use Apple's apple logo, the rainbow version included, or Total Replay's art; the repo is meant to be public. How: boot.efi draws whatever image com.apple.Boot.plist's `Boot Logo` key names (a file on the boot partition, e.g. `BootLogo.png`; see atv-linux-loader's README and example plist). Without the key it draws the grey Apple logo. So: add the PNG to the boot partition in mkimage.sh (the mcopy line) and the key to its plist. It is drawn over `Background Color` (0, black). Unknowns to test on the box first (`sudo mount /boot/atv`): the size and PNG flavour boot.efi accepts (start with a small 8-bit RGB PNG, no alpha), and where it places it.
- Total Replay updates. Releases (github.com/a2-4am/4cade, one `Total.Replay.hdv` asset each, 33,553,920 bytes): 5.0 2023-05, 5.0.1 2023-11, 5.1 2024-02, 5.2 2024-09, 6.0 and 6.0.1 2026-06, 6.1 2026-08 (built and tested with 6.1). So 1-3 a year, irregular (a 21-month gap before 6.0), with commits in between. Today an update means replacing assets/total-replay.hdv and rebuilding. Options: an on-box `totalreplay-update` that fetches the latest release (GitHub's releases/latest API), checks size and that it boots, keeps the old image to roll back to, then restarts the kiosk; or a check at boot that only reports a new version. Caveat: Total Replay saves preferences and high scores inside the .hdv, so replacing it loses them; find out whether they can be carried over (they live in a few files on the ProDOS volume).
- Publishing: the repo is local only (branch main). Before the first push: `git grep` for personal details (host names, home paths, IPs, email addresses) and private keys; they belong in CLAUDE.local.md or out/. The .gitignore keeps out:
  - out/: build output, including the private SSH key (out/ssh) and the box's SSH host keys (out/hostkeys).
  - env/root, logs and tarballs: the build environment, gigabytes, regenerated by env/bootstrap.sh.
  - assets/: Apple's boot.efi (proprietary), Dummy.kext, total-replay.hdv (free from Total Replay's project, but it contains commercial games). The README says where to get each.
  - CLAUDE.local.md: notes about one particular setup.
  - src/atv-linux-loader is a git submodule (clone with `--recurse-submodules`, or `git submodule update --init`).

## Upstream contributions (to send back, with thanks)
Fixes worth offering to the projects this box depends on. Patches live in patches/.
- **linapple** (github.com/linappleii/linapple):
  - patches/linapple-i386-snapshot-align.patch: the save-state `static_assert(snapshot_size_fixed_body == 132344)` fails on i386 (132340) because `uint64_t` members are only 4-byte aligned there; `alignas(8)` on two members fixes it. Upstream only builds on 64-bit today.
  - patches/linapple-stretch-speedup.patch: VideoStretch did a 64-bit division per pixel (`__divdi3` on 32-bit, the top cost on a 1 GHz CPU); replaced with exact stepping, plus an exact-2x fast path and memcpy of repeated rows. Byte-identical output (tested against upstream on 25 MB of cases).
  - patches/linapple-sdl2-window-surface.patch: when SDL hands out its software renderer, draw into the window surface directly and update only the rows that changed (at any scale, in blocks that scale exactly). 25.6 -> 60 fps on the Apple TV. Upstream may want it behind a check or option; it changes nothing for accelerated renderers.
  - Report: `--fullscreen` uses `SDL_WINDOW_FULLSCREEN`, a real mode change to the nearest mode (640x480 here). An option for `SDL_WINDOW_FULLSCREEN_DESKTOP` plus the existing aspect-fit scaling would suit TVs better.
  - Report: SDL2 frontend crashes inside Mesa's nouveau_dri.so on GeForce 7 (nv40) unless `SDL_RENDER_DRIVER=software SDL_FRAMEBUFFER_ACCELERATION=0`; worth a note in the docs (the bug itself is Mesa's).
- **Mesa** (nouveau nv40): segfault at `nouveau_pushbuf_kick` from SDL2's GL texture framebuffer on a G72. Only worth filing with a reproducer.
- **xf86-video-nouveau**: with EXA on nv4x, each XShmPutImage allocates and zeroes a new buffer (kernel_init_pages ~15% of CPU). Maybe report.
- **atv-linux-loader** (DistroHopper39B): a note for its docs: on HDMI, nouveau makes the picture purple (YCbCr read as RGB); blacklisting nouveau and using efifb (plus a write-combining MTRR) gives correct colours.
- **ALSA HDA (kernel, patch_hdmi)**: the Apple TV's SiI1390 (0x10951390) never reports presence or an ELD, so HDMI audio stays silent and mono until DIGI_CONVERT_1 and CVT_CHAN_COUNT are set by hand. A quirk for this codec (e.g. static_pcm_mapping, or treating the pin as always present) would make it work out of the box. Report with a codec#1 dump and the register values.
- **nouveau** (kernel): on the Apple TV, any nouveau modeset leaves the SiI1390 sending YCbCr the TV reads as RGB. Worth a report with dmesg and the DCB.

## linapple facts (upstream github.com/linappleii/linapple)
- Pinned to commit 0b22441 (2026-11-05). master uses CMake with `-DFRONTEND=sdl3|sdl2|sdl1|tui|headless`. Debian 12 has no SDL3, so use `-DFRONTEND=sdl2`. Build deps: g++ cmake libzip-dev libcurl4-openssl-dev zlib1g-dev imagemagick libsdl2-dev (sdl1 also needs libsdl1.2-dev libsdl-image1.2-dev).
- CLI: `--hd1 <file>` (inserts hard disk in slot 7), `-a/--autoboot`, `-c/--config`, `-f/--fullscreen`.

## Notes
- QEMU can test systemd/network/service logic (boot the kernel+initrd with `-kernel/-initrd`), but cannot reproduce boot.efi or the G72/nouveau/KMS behavior.
- Original Apple TV firmware has no native PXE/NetBoot; a local boot drive is required.
- /root on the stick is mode 0700; reading it from another machine needs sudo.
- Alpine/OpenRC was considered and rejected; stay on Debian.
- Working with whoever is at the TV: only they can judge colours, overscan and sound. tools/av-test (colour screens, plus tones per output) and tools/sound-test (spoken left/right) make those checks quick; a phone video helps (its stereo mics can't separate left from right, though).
