# andrew-waters/orchard#126: Handle the new runHook operation from ComposePlanner

https://github.com/andrew-waters/orchard/issues/126

- State: open
- Opened by: @andrew-waters, 13 Oct 2026

## Description

andrew-waters/compose is adding support for Compose's `post_start` and `pre_stop` service hooks (andrew-waters/compose#6, branch `6-docker-compose-post-start-pre-stop`).

This adds a new case to `ComposePlanner.Operation`:

```swift
case runHook(HookOperation)
```

`HookOperation` carries the service, container name, phase (`post_start` or `pre_stop`), index, command, environment, working directory, user and `failureIsFatal`. The planner emits it right after a `startContainer` in `up`, and right before a `stopContainer` of a running container in `down` and on recreate.

What this means for Orchard when it next bumps the package:

- An exhaustive `switch` over `Operation` will stop compiling until the case is handled.
- A `switch` with a `default` would silently skip hooks, which is the outcome to avoid: a file that relies on them would appear to run but not do what it says.

Running hooks in the Compose tab is out of scope for the compose work. The ask is that Orchard either lists hooks among the things it will not do (the same way it lists other ignored keys) or refuses the plan, rather than skipping them silently. `Service.postStart` and `Service.preStop` are available on the parsed model if listing them up front is easier than inspecting the plan.

Tracked from andrew-waters/compose#12.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/126-handle-the-new-runhook-operation-from/`: give each repo it touches a worktree there, on the branch `126-handle-the-new-runhook-operation-from`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/126-handle-the-new-runhook-operation-from/<name>" -b 126-handle-the-new-runhook-operation-from origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. You're in a sandbox: only the repos already under `projects/` are here (andrew-waters/orchard), and a clone made in it would vanish when it stops. If the issue needs another repo, stop and ask the user to clone it into `projects/` on their Mac and restart the session. Commits are signed for you. The repos' git dirs are read-only apart from what commits, fetches and worktrees write, so git config and hooks can't be changed, no upstream is recorded (push with `git push origin HEAD:126-handle-the-new-runhook-operation-from` and open the PR with `gh pr create --head <branch>`), branches can't be deleted, and an error about packed-refs.lock after a rebase or pull is expected and harmless.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/126-handle-the-new-runhook-operation-from/orchard" -b 126-handle-the-new-runhook-operation-from origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/126-handle-the-new-runhook-operation-from/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#126" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#126]` and a summary in its front matter as the harness's STANDARDS.md sets out, so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/126-handle-the-new-runhook-operation-from/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
