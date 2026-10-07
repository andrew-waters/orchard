# andrew-waters/orchard#120: Show files changed and lines added/removed in PR and people views to track PR size

https://github.com/andrew-waters/orchard/issues/120

## Description

## Summary

Add columns for PR size to the PR views and the people views:

- **Files changed**: total number of files changed
- **Lines added / removed**: line I/O (additions and deletions)

## Motivation

I want to gauge PR size across the team and track it as a metric over time.

## Proposed behaviour

- **PR views**: each PR row shows files changed, lines added and lines removed.
- **People views**: each person shows aggregated PR size figures for their PRs.

## Open questions

- How should the people views aggregate figures (totals, averages, medians, or several of these)?
- Should lines added and removed be separate columns, one combined column (for example `+120 / -45`), or both alongside a net or total figure?
- What time window should the people view metrics cover, and should it follow any existing date filters?
- Does "track it as a metric" mean only showing the columns, or also storing history or showing trends over time?
- Should generated or vendored files (lockfiles and so on) be excluded from the counts?
- Should the columns be sortable?
- Unknown: whether the data source orchard uses already provides these figures or needs extra API calls to fetch them.

## Acceptance criteria

- [ ] PR views show files changed, lines added and lines removed for each PR
- [ ] People views show aggregated PR size figures for each person
- [ ] Aggregation method and time window are decided and documented

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/120-show-files-changed-and-lines-added/`: give each repo it touches a worktree there, on the branch `120-show-files-changed-and-lines-added`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/120-show-files-changed-and-lines-added/<name>" -b 120-show-files-changed-and-lines-added origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/120-show-files-changed-and-lines-added/orchard" -b 120-show-files-changed-and-lines-added origin/HEAD`, and do everything there, the plan included.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#120" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#120]` and a summary in its front matter as the harness's STANDARDS.md sets out, so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/120-show-files-changed-and-lines-added/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
