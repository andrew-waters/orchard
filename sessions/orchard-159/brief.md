# andrew-waters/orchard#159: Add a disk usage view and a way to purge unused data

https://github.com/andrew-waters/orchard/issues/159

## Description

## Summary

Add a view that shows how much disk space Orchard's data is using, and add a way to purge data that is no longer used.

## Motivation

Right now there is no way to see how much disk space is being used or to reclaim it from inside the app.

## Proposed behaviour

### Disk usage view

- Show total disk usage for the data Orchard manages.
- Break the total down by data type or category, if that is practical.

### Purge unused data

- Provide an action that removes unused data.
- Show what will be removed, and how much space it will free, before anything is deleted.
- Ask for confirmation before deleting.

## Open questions / unknowns

- **Data in scope:** which kinds of data the view should cover (for example images, volumes, caches, build artifacts, logs) has not been decided.
- **Definition of "unused":** the criteria for treating data as unused are not yet defined (for example not referenced by anything running, or not accessed within some period).
- **Where the view lives:** whether this is a new screen, a panel inside an existing view, or a CLI command is undecided.
- **Purge granularity:** whether purging is all-or-nothing, per category, or per item is undecided.
- **Data source:** how sizes are calculated (an underlying tool or API versus walking the filesystem) and how expensive that is are unknown.
- **Safety:** whether purged data can be recovered, and whether there should be a dry-run mode, is undecided.

## Acceptance criteria (draft)

- [ ] A user can see the current disk usage of Orchard-managed data.
- [ ] A user can purge unused data after seeing a preview and confirming.
- [ ] Data that is in use is never removed by the purge action.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/159-add-a-disk-usage-view-and-a-way-to-purge/`: give each repo it touches a worktree there, on the branch `159-add-a-disk-usage-view-and-a-way-to-purge`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/159-add-a-disk-usage-view-and-a-way-to-purge/<name>" -b 159-add-a-disk-usage-view-and-a-way-to-purge origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/159-add-a-disk-usage-view-and-a-way-to-purge/orchard" -b 159-add-a-disk-usage-view-and-a-way-to-purge origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/159-add-a-disk-usage-view-and-a-way-to-purge/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#159" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/159-add-a-disk-usage-view-and-a-way-to-purge/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#159]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/159-add-a-disk-usage-view-and-a-way-to-purge/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
