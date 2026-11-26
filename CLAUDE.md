@docs/NOTES.md

## For Claude Code
- Start by checking `git status` and `git log` for work in progress. Untracked or modified files you didn't create may belong to another session: leave them alone.
- Find out what you can yourself (the code, the box over SSH, logs, `sudo fps`, tests/box.sh). Ask whoever is at the TV only about what needs their eyes or ears: colours, overscan, sound, the remote.
- When a change is done, say what you verified, what the person at the TV should check, and the command to write the stick if the image changed (they run anything needing root).
- Commit with a message that says why. Don't push or publish unless asked.
- `main` only takes pull requests, even from the owner: direct pushes and local merge commits are refused. To publish, work on a branch, push it, open a PR (`gh pr create`), wait for the required checks (`quick` and the three CodeQL analyses: `gh pr checks --watch`), then `gh pr merge --rebase`. Merges are rebase-only and the branch must be up to date with `main`, so rebase onto `main` rather than merging it in; the branch is deleted after merging. Commit as the GitHub login with its noreply address, with `TZ=UTC`.
- Commands: `tests/run` (add `TEST_BOX=1` when the box is involved); after changing a build input, `./build.sh && ./mkimage.sh && env/devroot init`; lint is shellcheck, run by tests/static.sh; `env/vuln-check` before publishing an image.
- Anything about one machine, TV, network or account goes in CLAUDE.local.md (gitignored; in a git worktree, read it from the main checkout). So do unfixed weaknesses: tracked files describe the security that is in place, not what is still open.
