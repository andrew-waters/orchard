# andrew-waters/gannin#107: Documentation

https://github.com/andrew-waters/gannin/issues/107

- State: open
- Opened by: @andrew-waters, 10 Oct 2026

## Description

A user docs site at gannin.ai/docs (Astro Starlight, deployed with the unchanged landing page): Get started, Concepts with a metrics glossary, ways to run sessions, a Settings reference for every pane and keyboard shortcuts, linked from Help, with app copy fixes and a CI check, issue template and planning prompt to keep it current.

Planned in [Documentation](https://github.com/andrew-waters/gannin/blob/HEAD/plans/2026-10-10-documentation.md).

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/107-documentation/`: give each repo it touches a worktree there, on the branch `107-documentation`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/107-documentation/<name>" -b 107-documentation origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. You're in a sandbox: only the repos already under `projects/` are here (andrew-waters/gannin), and a clone made in it would vanish when it stops. If the issue needs another repo, stop and ask the user to clone it into `projects/` on their Mac and restart the session. Commits are signed for you. The repos' git dirs are read-only apart from what commits, fetches and worktrees write, so git config and hooks can't be changed, no upstream is recorded (push with `git push origin HEAD` and open the PR with `gh pr create --head <branch>`), branches can't be deleted, and an error about packed-refs.lock after a rebase or pull is expected and harmless.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/107-documentation/orchard" -b 107-documentation origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/107-documentation/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- The issue lives in andrew-waters/gannin.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/gannin#107" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/gannin#107]` and a summary in its front matter as the harness's STANDARDS.md sets out, so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/107-documentation/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.

## Scheduled run

Gannin started this session by itself, for the routine "andrew-waters/gannin#107 Documentation". Nobody is watching it.

- Don't ask questions or wait for a plan to be approved: decide, write down why where the work is recorded (the plan, the commit, the pull request or the report), and carry on. If you can't go on without a person, stop and say why in your last message.
- You're in auto mode. A permission prompt or question waits for someone and holds the run up.
- It's stopped after 60 minutes or US$5.00 spent, whichever comes first, keeping what's done. Keep within that.
- Ready PR: once the change is committed, built and checked, push with `git push origin HEAD` and open a pull request ready for review. Don't merge it.
