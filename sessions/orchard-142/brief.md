# andrew-waters/orchard#142: Hiding the Dock icon makes the menu unavailable

https://github.com/andrew-waters/orchard/issues/142

- State: open
- Labels: bug
- Opened by: @pakohan, 22 Oct 2026

## Description

## Describe the bug

In the settings I chose to hide the dock icon, which broke full screen view. After restarting, the Dock icon is gone, but so is the menu bar, showing the Finders menu instead. Also, full screen does not work with the Dock icon hidden, and without the menu I don't know how to reset that setting to bring it back.

## To reproduce

Steps to reproduce the behaviour:

1. Go to 'Settings'
2. Click on 'Hide dock icon'
3. the macos menu bar for Orchard is missing

## Expected behaviour

I would like to be able to still access the menu, especially the settings

## Screenshots / logs

<img width="757" height="125" alt="Image" src="https://github.com/user-attachments/assets/82601da9-0603-4041-8ff7-e7356b32af7a" />

## Environment

- latest homebrew version
- latest macos version

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/142-hiding-the-dock-icon-makes-the-menu/`: give each repo it touches a worktree there, on the branch `142-hiding-the-dock-icon-makes-the-menu`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/142-hiding-the-dock-icon-makes-the-menu/<name>" -b 142-hiding-the-dock-icon-makes-the-menu origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/142-hiding-the-dock-icon-makes-the-menu/orchard" -b 142-hiding-the-dock-icon-makes-the-menu origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/142-hiding-the-dock-icon-makes-the-menu/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#142" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/142-hiding-the-dock-icon-makes-the-menu/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#142]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/142-hiding-the-dock-icon-makes-the-menu/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
