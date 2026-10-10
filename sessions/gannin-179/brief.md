# andrew-waters/gannin#179: Releases ship with a changelog, and a PR template checks it was updated

https://github.com/andrew-waters/gannin/issues/179

## Description

## Problem

The release process has no changelog step, so there's nowhere that records what changed between versions. There's also no pull request template, so nothing reminds the author of a PR to record their change (or to do the other pre-review checks). The harness's `skills/create-pull-request.md` notes this gap: "TODO: the harness doesn't define a PR template."

This affects anyone cutting a release and anyone trying to see what a given version changed.

## Proposal

1. **Changelog in the release process.** Every release should produce or publish a changelog for that version. The app's version comes from the release tag (`project.yml` keeps `MARKETING_VERSION` at `0.0.0`, which `ci.yml` enforces), so the changelog should be tied to the tag.
2. **A pull request template** (`.github/pull_request_template.md`) with a checklist. One item confirms the changelog was updated. Other items are still to be decided (see Unknowns).
3. **Reuse what andrew-waters/orchard already has** for changelogs and releases, rather than building something new.

## Acceptance

- [ ] Cutting a release produces or publishes a changelog entry for that version
- [ ] `.github/pull_request_template.md` exists and includes a "changelog updated" checkbox
- [ ] The template's other checklist items are agreed and included
- [ ] `skills/create-pull-request.md` in the harness is updated to use the template instead of its TODO

## Unknowns

- **What orchard's machinery is.** I couldn't read andrew-waters/orchard while drafting this, so I don't know which files, workflows or tools it uses (for example a `CHANGELOG.md`, release notes made from PRs, or a release workflow). Someone needs to list them here before work starts.
- **Where the changelog lives:** a `CHANGELOG.md` in the repo, the GitHub release notes, or both.
- **Who writes entries:** each PR author, or generated at release time from PRs or labels.
- **Which other checks go in the PR template** ("amongst other things"). The PR skill already lists candidates: linked issue (`Closes` or `Part of`), build run once, `CLAUDE.md` updated when behaviour changes, `MARKETING_VERSION` left at `0.0.0`, Verified section is honest, no Claude attribution. Which of these to include isn't decided.
- **Whether PRs with no user-facing change** (CI or docs, say) need an entry or can skip it.

## Context

- Existing machinery to reuse: andrew-waters/orchard
- Harness skill that will use the template: `skills/create-pull-request.md` (step 7 and its TODO)
- Release tooling in this repo: `ci.yml`, `project.yml`

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/179-releases-ship-with-a-changelog-and-a-pr/`: give each repo it touches a worktree there, on the branch `179-releases-ship-with-a-changelog-and-a-pr`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/179-releases-ship-with-a-changelog-and-a-pr/<name>" -b 179-releases-ship-with-a-changelog-and-a-pr origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. You're in a sandbox: only the repos already under `projects/` are here (andrew-waters/gannin), and a clone made in it would vanish when it stops. If the issue needs another repo, stop and ask the user to clone it into `projects/` on their Mac and restart the session. Commits are signed for you. The repos' git dirs are read-only apart from what commits, fetches and worktrees write, so git config and hooks can't be changed, no upstream is recorded (push with `git push origin HEAD` and open the PR with `gh pr create --head <branch>`), branches can't be deleted, and an error about packed-refs.lock after a rebase or pull is expected and harmless.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/179-releases-ship-with-a-changelog-and-a-pr/orchard" -b 179-releases-ship-with-a-changelog-and-a-pr origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/179-releases-ship-with-a-changelog-and-a-pr/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- The issue lives in andrew-waters/gannin.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/gannin#179" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/gannin#179]` and a summary in its front matter as the harness's STANDARDS.md sets out, so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/179-releases-ship-with-a-changelog-and-a-pr/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.

## Scheduled run

Gannin started this session by itself, for the routine "Weekend Pickup". Nobody is watching it.

- Don't ask questions or wait for a plan to be approved: decide, write down why where the work is recorded (the plan, the commit, the pull request or the report), and carry on. If you can't go on without a person, stop and say why in your last message.
- You're in auto mode. A permission prompt or question waits for someone and holds the run up.
- It's stopped after 60 minutes or US$5.00 spent, whichever comes first, keeping what's done. Keep within that.
- Ready PR: once the change is committed, built and checked, push with `git push origin HEAD` and open a pull request ready for review. Don't merge it.
