# andrew-waters/orchard#132: Bump apple/container to 1.6.0

https://github.com/andrew-waters/orchard/issues/132

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 20 Oct 2026

## Description

Orchard pins apple/container at **1.5.0** and containerization at **0.47.0** (`Orchard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`). Release 1.6.0 (https://github.com/apple/container/releases/tag/1.6.0) depends on containerization 0.52.1. Every other 1.6.0 feature issue depends on this one.

**Things that may break:**
- **Machine API (apple/container#2322).** Removes the image-script and ORAS user-setup extension points and changes `MachineConfiguration`, `MachineKeys`, `MachineUserSetup` and `MachineClient` under `Sources/Services/MachineAPIService/Client/`. `Orchard/Services/MachineBackend.swift` uses these types directly and may need changes to compile.
- **Build and builder moved to a CLI plugin (apple/container#2298, #2370).** Orchard shells out to `container build ... --progress plain` (`ImageBuildService.arguments(for:)`) and `container builder status --format json` (`BuilderService.swift:54`). I checked the 1.6.0 sources: both flags survive in the plugin (`Sources/Plugins/ContainerBuilder/BuilderStatus.swift`, `Sources/Plugins/ContainerBuild/Application.swift`). Only `builder list` lost `--format` and `--quiet`, and Orchard doesn't call it. Smoke test anyway.
- **Network attachments (apple/container#2390).** `AttachmentConfiguration` gained alias fields. Check any code in Orchard that builds or decodes attachments (`Models.swift`, `ContainerConfigForm.swift`).

**Clean-ups the release allows:**
- `container logs` now treats a missing log file as empty (#2393), and following an empty log no longer fails (#2377). If the log viewer works around either case, remove the workaround or limit it to older versions.
- `container image load` handles sparse images (#2385), and `image list` skips unreadable entries (#2157). Remove any defensive handling in Orchard that only existed for these.

**Steps:**
1. Update the package pin to `1.6.0` and resolve containerization to 0.52.1.
2. Fix compile errors, starting with `MachineBackend.swift`.
3. Run the affected unit tests (machines, builds, builder, networks) instead of the whole suite.
4. Manual smoke test against a 1.6.0 install: create, start and stop a container and a machine; build an image from the Images tab; check builder status in Settings; open logs on a container that has never written output.
5. Confirm a 1.5.x install still works: the dependency bump must not break older runtimes over XPC. If anything does break, note it in the PR and in `NewerVersion.swift` guidance.
6. Add a CHANGELOG entry.

**Checked by:** the app builds, the scoped tests pass, and the smoke test passes on 1.6.0 and on 1.5.x.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/132-bump-apple-container-to-1-6-0/`: give each repo it touches a worktree there, on the branch `132-bump-apple-container-to-1-6-0`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/132-bump-apple-container-to-1-6-0/<name>" -b 132-bump-apple-container-to-1-6-0 origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/132-bump-apple-container-to-1-6-0/orchard" -b 132-bump-apple-container-to-1-6-0 origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/132-bump-apple-container-to-1-6-0/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#132" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#132]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/132-bump-apple-container-to-1-6-0/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
