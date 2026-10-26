# andrew-waters/orchard#155: Offer to update the compose plugin when it is behind

https://github.com/andrew-waters/orchard/issues/155

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 26 Oct 2026

## Description

The Compose tab notices when the `container compose` CLI plugin is missing and offers to install it, and it reads the installed plugin's version (`container compose --version`). It never compares that version with anything, so someone on an older plugin is never told a newer one exists.

That matters because the window and the terminal can now disagree about the same file. Orchard compiles the compose package in (0.7.0 from andrew-waters/orchard#147), so the Compose tab honours a service's `platform:`. A 0.6.0 plugin reports the key as unsupported and ignores it, and because the finding is cosmetic the run goes ahead: `container compose up` brings the service up as arm64 while Orchard brings it up as amd64.

**Orchard work:**
- In `ComposePluginService`, compare the installed version with the latest release, which `latestRelease()` already fetches for **Install**, and add an "update available" state. Fetch it at most once per visit to the tab, and treat a failed lookup as "unknown", never as out of date.
- Consider also flagging a plugin older than the compose package Orchard links, since that is the version whose behaviour the window shows.
- Show the update in the Compose tab next to the installed version, with an **Update** button that reuses the install flow (download, check, one administrator prompt).
- Parse versions as numbers, so 0.10.0 is newer than 0.9.0, and leave a version that does not parse alone.
- README and CHANGELOG.

**Checked by:** with plugin 0.6.0 installed and 0.7.0 released, the Compose tab offers the update and installing it reports 0.7.0. With the latest installed, nothing is offered. With no network, the tab shows the installed version and no error.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/155-offer-to-update-the-compose-plugin-when/`: give each repo it touches a worktree there, on the branch `155-offer-to-update-the-compose-plugin-when`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/155-offer-to-update-the-compose-plugin-when/<name>" -b 155-offer-to-update-the-compose-plugin-when origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/155-offer-to-update-the-compose-plugin-when/orchard" -b 155-offer-to-update-the-compose-plugin-when origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/155-offer-to-update-the-compose-plugin-when/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#155" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/155-offer-to-update-the-compose-plugin-when/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#155]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/155-offer-to-update-the-compose-plugin-when/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
