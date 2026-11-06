# andrew-waters/orchard#167: Fullscreen hides buttons on top

https://github.com/andrew-waters/orchard/issues/167

- State: open
- Labels: bug
- Opened by: @pakohan, 5 Nov 2026

## Description

## Describe the bug

When entering full screen mode, the top row with the buttons is hidden

## To reproduce

Steps to reproduce the behaviour:

1. Open Orchard with Dock icon active
2. Click on full screen
3. See no butons

## Expected behaviour

I would expect the buttons to be available even in full screen mode

## Screenshots / logs

this is how it looks in full screen mode:

<img width="2038" height="133" alt="Image" src="https://github.com/user-attachments/assets/15eea5de-7d4f-4443-9572-a0aea69bcc2f" />

these are the buttons I can see when not in full screen:

<img width="886" height="115" alt="Image" src="https://github.com/user-attachments/assets/c80dc048-38e3-4e75-9160-6088c3f9adcb" />

## Environment

- Orchard version: latest
- macOS version: latest

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/167-fullscreen-hides-buttons-on-top/`: give each repo it touches a worktree there, on the branch `167-fullscreen-hides-buttons-on-top`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/167-fullscreen-hides-buttons-on-top/<name>" -b 167-fullscreen-hides-buttons-on-top origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/167-fullscreen-hides-buttons-on-top/orchard" -b 167-fullscreen-hides-buttons-on-top origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/167-fullscreen-hides-buttons-on-top/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#167" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/167-fullscreen-hides-buttons-on-top/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#167]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/167-fullscreen-hides-buttons-on-top/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
