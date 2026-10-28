# andrew-waters/orchard#161: Manage named volumes: a Volumes tab and named volumes in the run and edit forms

https://github.com/andrew-waters/orchard/issues/161

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 27 Oct 2026

## Description

## What problem are you trying to solve?

Apple container has first-class named volumes (`container volume create|list|inspect|delete|prune`), but Orchard has no way to see or manage them, and the run and edit forms can only add bind mounts. Volumes outlive their containers, so they don't belong in the Mounts tab, which is built from container configurations. Anonymous volumes in particular pile up unseen.

## Proposed solution

### Volumes tab

Backed by `ClientVolume` (`list`, `inspect`, `create`, `delete`, `volumeDiskUsage`) through `ContainerBackend`, so the boundary keeps app-owned types.

- [ ] List volumes with name, size, format, creation date and labels, and which containers use each one
- [ ] Mark anonymous volumes (label `com.apple.container.resource.anonymous`) and filter for unused ones
- [ ] Create a volume: name, optional size (as `container volume create -s`) and labels
- [ ] Delete one or several volumes; a volume in use fails with `volumeInUse`, so say which containers hold it
- [ ] Prune unused volumes, showing what will go and how much space it frees before asking to confirm (ties in with #159)
- [ ] Link the dashboard's Volumes tile to the tab
- [ ] Cmd+K entries: "create volume", "prune volumes", and each volume by name

### Named volumes in the run and edit forms

- [ ] Each mount row chooses bind mount, named volume or tmpfs
- [ ] Named volume: pick an existing volume or create one in place
- [ ] Container detail shows volume mounts by name and links to the volume

### Smaller

- [ ] Image inspect fills in the image config's `VOLUME` declarations in place of `volumes: nil`

Depends on #160, which adds volume support to `ContainerCreateSpec` and `createContainer`.

## Alternatives considered

Folding volumes into the Mounts tab. Mounts are per-container and derived from container configurations; volumes exist on their own, with or without containers, so a separate tab fits better. Mounts can stay for bind mounts.

## Additional context

`container volume --help` and `ClientVolume.swift` in apple/container 1.6.1.

## Comments

### @andrew-waters, 28 Oct 2026 at 8:54

When this lands, "Prune Volumes" could open the Free Up Space sheet from #159 with only the Volumes section, so there's one set of rules for what counts as unused (volumes mounted by name or by path are kept, and so are compose project volumes). `ContainerVolume` and `DiskPurge.volume(_:isMountedBy:)` are there to reuse.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/161-manage-named-volumes-a-volumes-tab-and/`: give each repo it touches a worktree there, on the branch `161-manage-named-volumes-a-volumes-tab-and`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/161-manage-named-volumes-a-volumes-tab-and/<name>" -b 161-manage-named-volumes-a-volumes-tab-and origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/161-manage-named-volumes-a-volumes-tab-and/orchard" -b 161-manage-named-volumes-a-volumes-tab-and origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/161-manage-named-volumes-a-volumes-tab-and/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#161" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/161-manage-named-volumes-a-volumes-tab-and/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#161]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/161-manage-named-volumes-a-volumes-tab-and/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
