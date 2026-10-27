# andrew-waters/orchard#160: Recreating a container turns named volumes and tmpfs mounts into virtiofs shares

https://github.com/andrew-waters/orchard/issues/160

- State: open
- Labels: bug
- Opened by: @andrew-waters, 27 Oct 2026

## Description

Orchard treats every container mount as a bind mount. A named volume (`container run -v pgdata:/data`), an anonymous volume or a tmpfs mount loses its type when Orchard reads it, and comes back as a virtiofs share when Orchard recreates the container.

## What happens

- `mapFilesystem` (`Orchard/Services/ModelMapping.swift`) only checks `isTmpfs` and `isVirtiofs`. A `.volume(name:...)` or `.block` filesystem maps to `MountType(tmpfs: nil, virtiofs: nil)`, and the volume name is dropped. The Mounts tab shows these as "Unknown".
- Recovering an auto-removed container (`recoverContainer`) and removing a mount (`deleteMounts`) in `ContainerListService` build `VolumeMapping(hostPath: mount.source, ...)` from every mount, whatever its type.
- `ContainerBackend.createContainer` then creates every entry as `.virtiofs(source:destination:options:)`. `ContainerCreateSpec.Volume` has no way to say anything else.

So a container with a named volume that is recovered, or has an unrelated mount removed, comes back with a virtiofs share of the volume's backing image path in place of the ext4 volume. The data in the volume is no longer mounted. A tmpfs mount comes back as a virtiofs share of an empty source.

Found by reading the code; not yet reproduced. The edit-container flow probably has the same problem and should be checked.

## To reproduce

1. `container run -d --name pg -v pgdata:/var/lib/postgresql/data -v /tmp/x:/x postgres`
2. In Orchard's Mounts tab, remove the `/tmp/x` mount from `pg`
3. `container inspect pg`: the `/var/lib/postgresql/data` mount is now virtiofs, not the `pgdata` volume

## Expected behaviour

A container's mounts survive a recreate unchanged: named and anonymous volumes stay volumes with the same name, tmpfs stays tmpfs, bind mounts stay bind mounts.

## Work

- [ ] Give `MountType` volume and block cases and keep the volume name and format in `Mount`; map them in `mapFilesystem` using `isVolume` and `volumeName`
- [ ] Give `ContainerCreateSpec.Volume` (and `ContainerRunConfig.VolumeMapping`) a kind: bind, named volume, tmpfs
- [ ] In `createContainer`, build `.volume` (resolving the name with `ClientVolume.inspect`), `.tmpfs` or `.virtiofs` from the kind
- [ ] Carry the kind through `recoverContainer`, `deleteMounts` and the edit-container path
- [ ] Show the right type in the Mounts tab in place of "Unknown"
- [ ] Changelog: named volumes and tmpfs mounts are kept when Orchard recreates a container

**Checked by:** unit tests for `mapFilesystem` over each filesystem type and for the spec round trip; manual run of the steps above, where `pgdata` is still mounted after the mount removal.

## Environment

- `container` version: 1.6.1 (the pinned client)

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/160-recreating-a-container-turns-named/`: give each repo it touches a worktree there, on the branch `160-recreating-a-container-turns-named`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/160-recreating-a-container-turns-named/<name>" -b 160-recreating-a-container-turns-named origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/160-recreating-a-container-turns-named/orchard" -b 160-recreating-a-container-turns-named origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/160-recreating-a-container-turns-named/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#160" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/160-recreating-a-container-turns-named/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#160]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/160-recreating-a-container-turns-named/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
