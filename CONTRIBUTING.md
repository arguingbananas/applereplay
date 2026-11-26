# Contributing to applereplay

Thanks for your interest. applereplay is a hobby project, so there's no
promised response time, but issues and pull requests are read and answered.

By taking part you agree to follow the [code of conduct](CODE_OF_CONDUCT.md).
Security problems go privately through [SECURITY.md](SECURITY.md), not in a
public issue.

## Ways to help

- **Hardware and game reports.** Tried it on your Apple TV? Say what worked and
  what didn't: hubs, sticks, keyboards, controllers, TVs, and games that
  misbehave. Use the "Hardware or game report" issue form.
- **Bug reports.** Something in the build, the image or the box doesn't work:
  use the "Bug report" form.
- **Code.** For anything bigger than a small fix, open an issue first so we can
  agree on the approach.

## Building and testing

The [README](README.md) has the full steps: what you need, the files you fetch
yourself, the build, the tests and writing the stick. In short:

```
env/bootstrap.sh                       # the build environment, once
./build.sh && ./mkimage.sh             # the image
tests/run                              # everything that needs no Apple TV
TEST_BOX=1 tests/run                   # also checks a running box
```

Shell scripts are checked with shellcheck and Python with pyflakes, both run by
`tests/static.sh`. Python scripts need 3.11 or newer.

## Pull requests

- Keep each PR to one change, and say what it does, why, and how you tested it:
  which tests you ran, and what you checked on a real Apple TV, if anything.
  Changes to what the box shows or plays are only really tested at a TV.
- Commit messages say why, not only what.
- The CI's quick tests must pass.
- Patches to linapple (in `patches/`) are offered under linapple's GPL-2.0;
  everything else is MIT. See the README's License section.

## What never goes in the repository

- Files that aren't ours to publish: Apple's boot loader, DummyKext, and the
  Total Replay disk image (it contains commercial games). `assets/` is
  gitignored for this reason.
- Build output, which includes private SSH keys (`out/` is gitignored).
- Anything about one particular machine, TV, network or account: addresses,
  host names, serial numbers. That belongs in `CLAUDE.local.md`, which is
  gitignored.

## Working with an AI assistant

applereplay was built with Claude Code, and it's set up for you to carry on
the same way (see the README). AI help is welcome in contributions too: say so
in your PR, and make sure you understand and have tested what you submit.
