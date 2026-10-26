# andrew-waters/orchard#145: Detect missing containers dependency and offer to install it

https://github.com/andrew-waters/orchard/issues/145

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 26 Oct 2026

## Description

## Summary

When orchard is installed but containers is not, orchard should notice, explain what is missing, and offer to install containers for the user rather than failing.

## Desired behaviour

1. On startup (or the first command that needs it), orchard checks whether containers is installed.
2. If it is missing, orchard tells the user that containers is required and why.
3. orchard offers to install it, and on confirmation runs the installation itself.
4. If the user declines, or installation fails, orchard shows clear manual install instructions and exits cleanly.

## Unknowns / to decide

- **Current behaviour:** what orchard does today when containers is missing (error message, crash, silent failure) has not been documented here.
- **Detection method:** how to reliably tell that containers is installed (binary on `PATH`, version check, a running service), and whether a minimum version is needed.
- **Install method:** which source to use (official installer package, Homebrew, direct download, something else), and whether it needs admin/`sudo` privileges.
- **Consent:** whether to always prompt before installing, and how this should behave in non-interactive contexts (CI, scripts). A `--yes` style flag may be needed.
- **Post-install steps:** whether containers needs starting or initialising after installation before orchard can use it.
- **Platforms:** which OS versions and architectures need supporting.

## Acceptance criteria

- [ ] Missing containers is detected before orchard tries to use it.
- [ ] The user sees a clear explanation and an install prompt.
- [ ] Accepting the prompt installs containers, and orchard then continues or tells the user what to do next.
- [ ] Declining, or a failed install, shows manual install instructions and a non-zero exit.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/145-detect-missing-containers-dependency-and/`: give each repo it touches a worktree there, on the branch `145-detect-missing-containers-dependency-and`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/145-detect-missing-containers-dependency-and/<name>" -b 145-detect-missing-containers-dependency-and origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/145-detect-missing-containers-dependency-and/orchard" -b 145-detect-missing-containers-dependency-and origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/145-detect-missing-containers-dependency-and/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#145" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/145-detect-missing-containers-dependency-and/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#145]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/145-detect-missing-containers-dependency-and/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
