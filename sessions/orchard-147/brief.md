# andrew-waters/orchard#147: Choose the platform when creating a container

https://github.com/andrew-waters/orchard/issues/147

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 26 Oct 2026

## Description

Orchard always creates containers for the host platform. `ContainerBackend.createContainer` hard-codes `ContainerizationOCI.Platform.current` (around line 534) for the snapshot, the image config and the kernel. So an image published only for `linux/amd64` can't be run from Orchard, even though Apple container runs it under Rosetta, and there's no way to choose a variant of a multi-platform image. The CLI has had `--arch`, `--os` and `--platform` on `run`/`create` for a while.

apple/container 1.6.1 makes this easier: `run` and `create` now infer the OS, architecture and runtime from the image's OCI index (or manifest and config), and the images service gains an `imagePlatforms` route (apple/container#2422). Runtime defaults to `container-runtime-<os>` unless `--runtime` is set.

**Orchard work:**
- Add a Platform field to the run/create form (`RunContainer.swift` / `ContainerConfigForm.swift`). The default is "Automatic (from image)", followed by the platforms the image actually offers. Read them from `imagePlatforms` on 1.6.1 or later, or from the image index on older versions.
- Carry the choice on `ContainerCreateSpec` and use it in place of `Platform.current` for `getCreateSnapshot`, `image.config(for:)` and the kernel lookup. "Automatic" should match the CLI: choose the host platform if the image has it, otherwise the one the image provides.
- If an amd64 variant is selected and Rosetta isn't available, say so before creating, not as a runtime failure.
- Keep the platform on edit/recreate and compose `up` (a compose service's `platform:` key should map to it).
- Show the container's platform in its detail view if it isn't the host's.
- Update README.md, the site guide and CHANGELOG.

**Checked by:** an amd64-only image runs from Orchard on Apple silicon. A multi-platform image defaults to arm64 and can be switched to amd64. Editing or recreating keeps the choice. A compose service with `platform: linux/amd64` comes up as amd64.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/147-choose-the-platform-when-creating-a/`: give each repo it touches a worktree there, on the branch `147-choose-the-platform-when-creating-a`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/147-choose-the-platform-when-creating-a/<name>" -b 147-choose-the-platform-when-creating-a origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/147-choose-the-platform-when-creating-a/orchard" -b 147-choose-the-platform-when-creating-a origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/147-choose-the-platform-when-creating-a/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#147" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/147-choose-the-platform-when-creating-a/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#147]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/147-choose-the-platform-when-creating-a/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
