# andrew-waters/orchard#133: Commit a container to an image

https://github.com/andrew-waters/orchard/issues/133

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 20 Oct 2026

## Description

apple/container 1.6.0 adds `container commit <container-id> <reference>` (apple/container#1762), which creates an image from a container's filesystem. On a running container it takes a runtime snapshot first, the same way `export` does. Orchard already has "Export as tar"; commit belongs next to it.

**How upstream implements it:** the command is assembled on the CLI side (`Sources/ContainerCommands/Container/ContainerCommit.swift`, plus `Image/ImageLoad.swift` and `Image/OCIImageArchive.swift`). It exports the filesystem, wraps it as an OCI image archive and loads that archive into the image store. There is no new XPC route. Read those files at the `1.6.0` tag before choosing an approach:
- **Preferred:** reuse the library code if `OCIImageArchive` is reachable from a product Orchard links, and drive it after the existing XPC export (`ContainerBackend.exportContainer`, `ContainerBackend.swift:242`). This matches how Orchard drives everything else.
- **Fallback:** shell out to `container commit` the way builds do. Document why in the PR.

Check what the committed image inherits from the source image (entrypoint, cmd, env, workdir, labels) and say so in the UI if it is only the filesystem.

**Orchard work:**
- Add a "Commit to Image" action in `ContainerDetailHeader.swift` beside export, and in the containers list context menu. It opens a sheet asking for the image reference, suggesting `<container-name>:latest` and validating it the same way the build sheet validates tags.
- Show progress while committing, and when it finishes, link to the new image in the Images tab (`orchard://image/<reference>`), the way finished builds cross-link.
- Add a Cmd+K palette action ("commit web").
- Offer it only on container 1.6.0 or later (`SystemService.containerVersion`).
- Add a test double to `UITestSupport.swift` next to `exportContainer`.
- Update the Orchard Features list in README.md, the site, and CHANGELOG.

**Depends on:** #132 (dependency bump to container 1.6.0).

**Checked by:** committing a running container and a stopped container both produce an image that appears in Images; running that image shows the changed files; committing with a reference that already exists either overwrites it or asks first (decide which, and test it).

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/133-commit-a-container-to-an-image/`: give each repo it touches a worktree there, on the branch `133-commit-a-container-to-an-image`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/133-commit-a-container-to-an-image/<name>" -b 133-commit-a-container-to-an-image origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/133-commit-a-container-to-an-image/orchard" -b 133-commit-a-container-to-an-image origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/133-commit-a-container-to-an-image/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#133" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#133]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/133-commit-a-container-to-an-image/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
