# andrew-waters/orchard#126: Handle the new runHook operation from ComposePlanner

https://github.com/andrew-waters/orchard/issues/126

- State: open
- Opened by: @andrew-waters, 13 Oct 2026

## Description

andrew-waters/compose is adding support for Compose's `post_start` and `pre_stop` service hooks (andrew-waters/compose#6, branch `6-docker-compose-post-start-pre-stop`).

This adds a new case to `ComposePlanner.Operation`:

```swift
case runHook(HookOperation)
```

`HookOperation` carries the service, container name, phase (`post_start` or `pre_stop`), index, command, environment, working directory, user and `failureIsFatal`. The planner emits it right after a `startContainer` in `up`, and right before a `stopContainer` of a running container in `down` and on recreate.

What this means for Orchard when it next bumps the package:

- An exhaustive `switch` over `Operation` will stop compiling until the case is handled.
- A `switch` with a `default` would silently skip hooks, which is the outcome to avoid: a file that relies on them would appear to run but not do what it says.

Running hooks in the Compose tab is out of scope for the compose work. The ask is that Orchard either lists hooks among the things it will not do (the same way it lists other ignored keys) or refuses the plan, rather than skipping them silently. `Service.postStart` and `Service.preStop` are available on the parsed model if listing them up front is easier than inspecting the plan.

Tracked from andrew-waters/compose#12.

## Plans and requirements

From the team's harness repo, andrew-waters/orchard, which keeps plans, requirements and findings beside the code. Those about this issue are here in full; the rest mention it.

### Handle the new runHook operation from ComposePlanner

Plan, in progress, about this issue: `plans/2026-10-13-handle-the-new-runhook-operation-from.md` (https://github.com/andrew-waters/orchard/blob/main/plans/2026-10-13-handle-the-new-runhook-operation-from.md)

The compose package (0.5.0) plans post_start and pre_stop hooks as Operation.runHook and can run them. Orchard must handle the new case when it bumps: run hooks, or list them as not honoured, but never skip them silently.

# Handle the new runHook operation from ComposePlanner

The compose package (0.5.0) plans post_start and pre_stop hooks as Operation.runHook and can run them. Orchard must handle the new case when it bumps: run hooks, or list them as not honoured, but never skip them silently.

## Requirement

In full in [requirements/handle-the-new-runhook-operation-from.md](../requirements/handle-the-new-runhook-operation-from.md).

**Problem:** andrew-waters/compose#13 (in the 0.5.0 tag) adds ComposePlanner.Operation.runHook for Compose post_start and pre_stop hooks, and marks both keys as supported. Orchard does not run hooks: when it bumps the package its exhaustive switches stop compiling, a default case would make hooks vanish silently, and because the keys are now 'supported' Orchard's findings would not list them either. A compose file that relies on hooks (seeding a database, registering with a proxy, draining before stop) would appear to come up correctly while doing less than it says.

**Goal:** Orchard's Compose tab runs post_start and pre_stop hooks as the compose file declares them, so a project behaves the same in Orchard as with the compose plugin.

**Who it's for:** People who run compose projects in Orchard's Compose tab whose files use post_start or pre_stop.

**Scope:**

1. Bump the compose package to 0.5.0 so Orchard plans runHook operations
2. Run each post_start hook in the running container after it starts, and each pre_stop hook before it stops, on up, down and recreate
3. Treat hook failures as the compose plugin does: a failing post_start (failureIsFatal) fails the up, skips later steps and leaves the container in place; a failing pre_stop is reported and the stop goes ahead
4. Show each hook as its own row in the Compose run, with its latest output line as live detail; on failure, the message names the hook, its exit status and its last few output lines
5. Run hooks only where ComposePlanner plans them: up, down and recreate in the Compose tab
6. Move to the compose 0.5.0 labels (com.compose.*), accepting that containers created with the old labels are no longer recognised

**Out of scope:**

- A full, openable transcript of hook output
- Running hooks when a compose container is started or stopped outside a Compose plan (Containers tab, menu bar)
- Recognising or migrating containers created with the old com.container-compose.* labels

**Acceptance criteria:**

- **R1** When Orchard is built against compose 0.5.0, the system shall handle every ComposePlanner.Operation case explicitly, with no default case that could skip a future operation silently.
- **R2** When a Compose up starts a container whose service declares post_start hooks, the system shall run each hook in that container, in declared order, after the container starts and before the plan's next step.
- **R3** When a Compose down or recreate stops a running container whose service declares pre_stop hooks, the system shall run each hook in that container, in declared order, before stopping it.
- **R4** When a hook runs, the system shall run its command with the hook's environment added to the container's, and its working directory and user when set, otherwise the container process's own.
- **R5** When a hook marked failureIsFatal (post_start) fails or cannot start, the system shall mark the run failed, mark every later step skipped, and leave the container in place.
- **R6** When a hook not marked failureIsFatal (any pre_stop) fails or cannot start, the system shall show the failure on that hook's row and carry on with the plan, including stopping the container.
- **R7** While a hook runs, the system shall show it as its own row in the Compose run naming its phase, index and service, with the hook's latest output line as the row's detail.
- **R8** When a hook fails, the system shall report a message naming the hook (phase, index, service), its exit status or why it could not start, and its last few lines of output.
- **R9** When a compose container is started or stopped outside a Compose plan (Containers tab, menu bar), the system shall not run its hooks.
- **R10** When a compose file declares post_start or pre_stop, the system shall not list them as not honoured or ignored in the review sheet or the Problems tab.
- **R11** When Orchard ships the compose 0.5.0 bump, the changelog shall say that projects brought up with earlier versions are no longer recognised, and that running down with the old version (or removing the containers) and up again fixes it.

**Decisions:**

- When a compose file has post_start or pre_stop hooks, what should Orchard do? **Run them in the Compose tab, now that compose 0.5.0 plans them with everything needed. Supersedes an earlier answer to list them as not honoured, given before running was offered as a realistic option.**
- What should happen when a hook fails? **Match the compose plugin, driven by failureIsFatal: failing post_start fails up, later steps skipped, container left in place; failing pre_stop is reported and the stop continues.**
- How much of a hook's output should the Compose run show? **A row per hook with the latest output line as detail; on failure, the hook, exit status and last few lines. No full transcript.**
- Should hooks run when a compose container is started or stopped outside a Compose up/down? **No. Only where ComposePlanner plans them (up, down, recreate in the Compose tab), matching the plugin.**
- After the bump, how should Orchard treat containers with the old com.container-compose.* labels? **Accept the break: they are no longer recognised; people bring projects down and up again.**
- Are the requirements R1-R11 right? **Approved as written, including the R11 changelog note.**

## Design

**Shape.** Orchard already executes ComposePlanner plans itself, one operation at a time, in `ComposeService`. Hooks become one more operation it performs, following the compose plugin's behaviour (`Sources/compose/Runtime.swift`) so a file does the same thing in Orchard and on the CLI.

**1. Run a process in a running container (backend).** Add to `ContainerBackend` a method along the lines of `runProcess(in containerID:, command:, environment:, workingDirectory:, user:, onOutput:) async throws -> Int32`. The real backend does what the plugin does: `ContainerClient().get` the container, refuse if it is not running, start from its `initProcess` configuration, override executable and arguments, append the hook's environment, set working directory and user when given, `terminal = false`, `createProcess` with stdout/stderr pipes, close the write ends, start, stream lines to `onOutput`, `wait`, then give the output up to 3 seconds to drain (a hook that backgrounds a daemon holds the pipe open). Errors go through `mapContainerError`. `MockContainerBackend` gains a handler and call record in the existing style. (R4)

**2. Bump compose to 0.5.0.** Pin `upToNextMinor` from 0.5.0 in the project and `Package.resolved`. Labels switch to `com.compose.*` through `ProjectIdentity` with no code change; projects brought up earlier are no longer recognised, which the room has accepted, and the changelog says so with the fix (down with the old version or remove the containers, then up). (R11)

**3. Handle `runHook` in `ComposeService`.** Both exhaustive switches gain the case with no `default` (R1):
- `step(for:)`: activity "Running" (or "Hook"), summary from the package's `Operation.summary`, service set, so each hook is its own row naming phase, index and service (R7). The planner already orders hooks after `startContainer` and before `stopContainer` (R2, R3).
- `perform`: calls `backend.runProcess`, feeding each output line into the row's detail through `updateDetail`, keeping the last few lines; a non-zero exit or a failure to start throws a `HookFailure` whose message names the hook, exit status or reason, and last lines, worded as the plugin words it (R7, R8).
- `execute`: when the failing operation is a hook with `failureIsFatal == false`, mark that row failed with the message, raise the alert, and carry on; otherwise keep today's behaviour (run failed, later steps skipped, nothing rolled back, so the container stays in place) (R5, R6).

**4. Nothing elsewhere.** Containers tab and menu bar Start/Stop call the backend directly and never see a plan, so they run no hooks (R9). Hooks are `.supported` in compose's `KeySupport`, so the review sheet and Problems tab do not list them (R10); a test pins both.

**Checks.** Unit tests in `OrchardTests/ComposeTests.swift` with `MockContainerBackend`: hook rows and order, fatal and non-fatal failure paths, message content, detail updates, no findings for hook keys. A manual run of a sample file with a `post_start` that writes a file and a failing `pre_stop` against a real runtime, since the backend method cannot be unit-tested without one.

**Shared logic later.** The hook outcome rules, failure message and output bounding are ported into Orchard now (a small `ComposeHooks` type beside `ComposeService`, kept close to the plugin's wording). A follow-up on andrew-waters/compose asks to expose them from a library product; when that ships, Orchard swaps its copy for the package's.

**Dependencies.** The 0.5.0 tag exists but has no GitHub release or notes; SwiftPM resolves tags, so this does not block, but whoever looks after compose may want to publish the release.

**Areas it touches:**

- `andrew-waters/orchard` `Orchard/Services/ComposeService.swift#L362-L425`: Two exhaustive switches over ComposePlanner.Operation: step(for:) builds the run row, perform(_:) executes it. Both stop compiling when runHook is added.
- `andrew-waters/orchard` `Orchard/Services/ContainerBackend.swift#L316-L330`: Orchard already builds ProcessConfiguration for container create; whether it can start a process in a running container is unchecked.
- `andrew-waters/orchard` `Orchard/Services/ComposeService.swift#L322-L358`: execute(_:) runs operations in order; any thrown error fails the run and marks later steps skipped. Non-fatal hooks need a path that records the failure on the row and continues.
- `andrew-waters/orchard` `Orchard/Services/ContainerBackend.swift#L111-L135`: ContainerBackend has no way to run a process in a running container. A new method is needed; the existing ones wrap ContainerClient calls and map errors with mapContainerError.
- `andrew-waters/orchard` `Orchard/Services/ComposeProjects.swift#L41-L80`: Project grouping reads ProjectIdentity.projectLabel/serviceLabel symbolically; nothing in Orchard, its tests or site hard-codes com.container-compose.*, so the label rename follows the bump automatically.

**Patterns to follow:**

- `andrew-waters/orchard` `Orchard/Views/Features/Compose/AddComposeProject.swift#L38-L62`: Review sheet already groups findings into 'Will not be honoured' (behavioural) and 'Ignored' (cosmetic). The natural home for hooks.
- `andrew-waters/orchard` `Orchard/Views/Features/Compose/ComposeProjectDetail.swift#L193-L245`: Problems tab groups findings as 'Not possible on this runtime', 'Not implemented yet' and 'Not a compose key'; behavioural findings feed the tab's count.
- `andrew-waters/compose` `Sources/compose/Runtime.swift#L60-L200`: The compose CLI plugin already runs hooks: a new process in the running container like container exec, environment/workdir/user from the hook over the service's; fatal post_start fails up and leaves the container; failing pre_stop is reported and the stop continues. A reference implementation Orchard could follow.
- `andrew-waters/orchard` `Orchard/Services/ContainerBackend.swift#L245-L251`: bootstrapAndStart shows the ContainerClient process pattern (create process with stdio, start) that a hook runner would extend with createProcess, wait and output pipes.
- `andrew-waters/orchard` `OrchardTests/Mocks.swift#L79-L260`: MockContainerBackend fakes each backend call with a handler closure and a call count; a new runProcess method needs the same so ComposeService hook handling can be tested without a runtime.
- `andrew-waters/orchard` `Orchard/Services/ComposeService.swift#L432-L441`: pullDetail/updateDetail feed live progress into a step's detail; hook output lines can use the same path for R7.

**Risks:**

- `andrew-waters/compose` `Sources/ComposeModel/KeySupport.swift#L154-L155`: post_start and pre_stop are now .supported, so the package's findings will not mention them. Orchard must raise its own finding or the hooks disappear from view.
- `andrew-waters/orchard` `Orchard.xcodeproj/project.pbxproj#L635-L638`: Orchard pins compose upToNextMinor from 0.3.0. Hooks ship in the 0.5.0 tag (no GitHub release or notes yet), so the bump is a deliberate minor-version step and may bring other 0.4/0.5 changes.
- `andrew-waters/compose` `Sources/ComposePlanner/ProjectIdentity.swift#L15-L20`: Between 0.3.0 and 0.5.0 the labels changed from com.container-compose.{project,service,hash} to com.compose.*. Orchard groups projects by ProjectIdentity.projectLabel (Orchard/Services/ComposeProjects.swift#L54), so after the bump existing projects would vanish from the Compose tab and up would collide with existing container names.
- `andrew-waters/compose` `Sources/compose/Runtime.swift#L81-L200`: The plugin's hook rules (HookOutcome, HookFailure message, bounded output transcript, 3s drain for backgrounded processes) live in the executable target, not a library product, so Orchard cannot import them. Porting means two copies that can drift.
- `andrew-waters/compose` `Package.swift#L20`: compose needs apple/container 1.4.1 or later; Orchard resolves 1.5.0, so ContainerClient.createProcess is available. Compatible, but a container bump on either side could pull them apart.

**Decisions:**

- How should Orchard get the plugin's hook rules (outcome, failure message, output bounding), which are not in an importable library? **Port them into Orchard now, following the plugin's rules and wording, and file a compose issue to move them into a library product so Orchard can switch to it later.**
- Is the design right? **Approved: backend runProcess, bump to 0.5.0, runHook handled in ComposeService with ported hook rules, compose follow-up to share them.**

## Tasks

1. [andrew-waters/orchard#127](https://github.com/andrew-waters/orchard/issues/127) Run a process in a running container from ContainerBackend (satisfies R4)
2. [andrew-waters/orchard#128](https://github.com/andrew-waters/orchard/issues/128) Bump compose to 0.5.0 and run hooks in Compose plans (satisfies R1, R2, R3, R5, R6, R9, R10, R11)
3. [andrew-waters/orchard#129](https://github.com/andrew-waters/orchard/issues/129) Show hook output and clear failure messages in the Compose run (satisfies R7, R8)
4. [andrew-waters/orchard#130](https://github.com/andrew-waters/orchard/issues/130) Expose hook outcome and failure message from a compose library

**Decisions:**

- Are the four tasks right? **Approved as written.**

## From the room

- 0.5.0 has support for runnign them - that wasnt an option (requirements)

### Handle the new runHook operation from ComposePlanner

Requirement, in progress, about this issue: `requirements/handle-the-new-runhook-operation-from.md` (https://github.com/andrew-waters/orchard/blob/main/requirements/handle-the-new-runhook-operation-from.md)

Orchard's Compose tab runs post_start and pre_stop hooks as the compose file declares them, so a project behaves the same in Orchard as with the compose plugin.

# Handle the new runHook operation from ComposePlanner

## Problem

andrew-waters/compose#13 (in the 0.5.0 tag) adds ComposePlanner.Operation.runHook for Compose post_start and pre_stop hooks, and marks both keys as supported. Orchard does not run hooks: when it bumps the package its exhaustive switches stop compiling, a default case would make hooks vanish silently, and because the keys are now 'supported' Orchard's findings would not list them either. A compose file that relies on hooks (seeding a database, registering with a proxy, draining before stop) would appear to come up correctly while doing less than it says.

## Goal

Orchard's Compose tab runs post_start and pre_stop hooks as the compose file declares them, so a project behaves the same in Orchard as with the compose plugin.

## Who it's for

People who run compose projects in Orchard's Compose tab whose files use post_start or pre_stop.

## Requirements

1. Bump the compose package to 0.5.0 so Orchard plans runHook operations
2. Run each post_start hook in the running container after it starts, and each pre_stop hook before it stops, on up, down and recreate
3. Treat hook failures as the compose plugin does: a failing post_start (failureIsFatal) fails the up, skips later steps and leaves the container in place; a failing pre_stop is reported and the stop goes ahead
4. Show each hook as its own row in the Compose run, with its latest output line as live detail; on failure, the message names the hook, its exit status and its last few output lines
5. Run hooks only where ComposePlanner plans them: up, down and recreate in the Compose tab
6. Move to the compose 0.5.0 labels (com.compose.*), accepting that containers created with the old labels are no longer recognised

## Out of scope

- A full, openable transcript of hook output
- Running hooks when a compose container is started or stopped outside a Compose plan (Containers tab, menu bar)
- Recognising or migrating containers created with the old com.container-compose.* labels

## Acceptance criteria

- **R1** When Orchard is built against compose 0.5.0, the system shall handle every ComposePlanner.Operation case explicitly, with no default case that could skip a future operation silently.
- **R2** When a Compose up starts a container whose service declares post_start hooks, the system shall run each hook in that container, in declared order, after the container starts and before the plan's next step.
- **R3** When a Compose down or recreate stops a running container whose service declares pre_stop hooks, the system shall run each hook in that container, in declared order, before stopping it.
- **R4** When a hook runs, the system shall run its command with the hook's environment added to the container's, and its working directory and user when set, otherwise the container process's own.
- **R5** When a hook marked failureIsFatal (post_start) fails or cannot start, the system shall mark the run failed, mark every later step skipped, and leave the container in place.
- **R6** When a hook not marked failureIsFatal (any pre_stop) fails or cannot start, the system shall show the failure on that hook's row and carry on with the plan, including stopping the container.
- **R7** While a hook runs, the system shall show it as its own row in the Compose run naming its phase, index and service, with the hook's latest output line as the row's detail.
- **R8** When a hook fails, the system shall report a message naming the hook (phase, index, service), its exit status or why it could not start, and its last few lines of output.
- **R9** When a compose container is started or stopped outside a Compose plan (Containers tab, menu bar), the system shall not run its hooks.
- **R10** When a compose file declares post_start or pre_stop, the system shall not list them as not honoured or ignored in the review sheet or the Problems tab.
- **R11** When Orchard ships the compose 0.5.0 bump, the changelog shall say that projects brought up with earlier versions are no longer recognised, and that running down with the old version (or removing the containers) and up again fixes it.

Planned in [plans/2026-10-13-handle-the-new-runhook-operation-from.md](../plans/2026-10-13-handle-the-new-runhook-operation-from.md).

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/126-handle-the-new-runhook-operation-from/`: give each repo it touches a worktree there, on the branch `126-handle-the-new-runhook-operation-from`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/126-handle-the-new-runhook-operation-from/<name>" -b 126-handle-the-new-runhook-operation-from origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/126-handle-the-new-runhook-operation-from/orchard" -b 126-handle-the-new-runhook-operation-from origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/126-handle-the-new-runhook-operation-from/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#126" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#126]` and a summary in its front matter as the harness's STANDARDS.md sets out, so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/126-handle-the-new-runhook-operation-from/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
