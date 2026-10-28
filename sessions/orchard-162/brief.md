# andrew-waters/orchard#162: Create and mount compose named and anonymous volumes

https://github.com/andrew-waters/orchard/issues/162

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 27 Oct 2026

## Description

## What problem are you trying to solve?

Compose projects that use named or anonymous volumes lose those mounts. The compose library's parser drops them with a note ("`<name>` is a named volume, and nothing here creates one yet; the mount is dropped"), and `ComposePlanner.CreateOperation.Mount` can only describe a host path. Databases are the most common reason a compose file declares volumes, so a `postgres` or `redis` service comes up without its data volume and loses its data when recreated.

## Proposed solution

In andrew-waters/compose:

- [ ] Keep `.named` and `.anonymous` mounts in the parser in place of dropping them
- [ ] Give `CreateOperation.Mount` a source kind: bind path, named volume, anonymous volume
- [ ] Plan the top-level `volumes:` entries: create those that don't exist, scoped to the project (`<project>_<key>` unless `name:` is set) and labelled with the project, honour `external: true` by requiring the volume to exist
- [ ] `down` leaves volumes alone; `down -v` (or its equivalent) removes the project's named and anonymous volumes

In Orchard:

- [ ] `ComposeService.createSpec(from:)` maps each mount kind onto the volume-aware `ContainerCreateSpec`
- [ ] Carry out volume-create and volume-remove operations through `ContainerBackend`
- [ ] Offer to remove the project's volumes when taking a project down, defaulting to keep
- [ ] Changelog: compose named and anonymous volumes are created and mounted, with the compose version this takes

Depends on #160 (volume support in `ContainerCreateSpec` and `createContainer`), and works best with #161 so people can see what compose created.

**Checked by:** planner tests for named, anonymous and external volumes and `down -v`; manual run of a compose file with a `postgres` service on a named volume, where data survives `down` and `up` and goes with `down -v`.

## Alternatives considered

Bind-mounting a directory under the project in place of a volume. It changes what compose files mean and gives worse performance for database workloads than an ext4 volume.

## Additional context

`projects/compose/Sources/ComposeParser/ServiceParsing.swift` (the dropped mounts) and `Sources/ComposePlanner/Operation.swift` (`CreateOperation.Mount`).

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/162-create-and-mount-compose-named-and/`: give each repo it touches a worktree there, on the branch `162-create-and-mount-compose-named-and`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/162-create-and-mount-compose-named-and/<name>" -b 162-create-and-mount-compose-named-and origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/162-create-and-mount-compose-named-and/orchard" -b 162-create-and-mount-compose-named-and origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/162-create-and-mount-compose-named-and/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#162" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/162-create-and-mount-compose-named-and/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#162]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/162-create-and-mount-compose-named-and/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
