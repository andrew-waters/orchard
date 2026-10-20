# andrew-waters/orchard#132: Bump apple/container to 1.6.0

https://github.com/andrew-waters/orchard/issues/132

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 20 Oct 2026

## Description

(Not loaded in Gannin yet. `gh issue view 132 --repo andrew-waters/orchard --comments` has it.)

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/132-bump-apple-container-to-1-6-0/`: give each repo it touches a worktree there, on the branch `132-bump-apple-container-to-1-6-0`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/132-bump-apple-container-to-1-6-0/<name>" -b 132-bump-apple-container-to-1-6-0 origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. You're in a sandbox: only the repos already under `projects/` are here (andrew-waters/orchard), and a clone made in it would vanish when it stops. If the issue needs another repo, stop and ask the user to clone it into `projects/` on their Mac and restart the session. Commits are signed for you. The repos' git dirs are read-only apart from what commits, fetches and worktrees write, so git config and hooks can't be changed, no upstream is recorded (push with `git push origin HEAD:132-bump-apple-container-to-1-6-0` and open the PR with `gh pr create --head <branch>`), branches can't be deleted, and an error about packed-refs.lock after a rebase or pull is expected and harmless.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/132-bump-apple-container-to-1-6-0/orchard" -b 132-bump-apple-container-to-1-6-0 origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/132-bump-apple-container-to-1-6-0/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and stop there: this run is Local only, so don't push or open a pull request (see Scheduled run).
- A plan for this issue goes in its folder as `.worktrees/132-bump-apple-container-to-1-6-0/plan.md`, with `issues: [andrew-waters/orchard#132]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else). This run is Local only and can't push it to the harness; whoever picks the branch up moves it in.
- `.worktrees/132-bump-apple-container-to-1-6-0/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.

## Scheduled run

Gannin started this session by itself, for the routine "Now". Nobody is watching it.

- Don't ask questions or wait for a plan to be approved: decide, write down why where the work is recorded (the plan, the commit, the pull request or the report), and carry on. If you can't go on without a person, stop and say why in your last message.
- You're in auto mode. A permission prompt or question waits for someone and holds the run up.
- It's stopped after 60 minutes or US$5.00 spent, whichever comes first, keeping what's done. Keep within that.
- Local only: commit your work on this branch in its worktrees, and stop there. Don't push, open or update a pull request, or comment on GitHub; Gannin won't let `git push` or `gh pr create` run. Someone will look at the branch.
