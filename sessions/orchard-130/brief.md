# andrew-waters/orchard#130: Expose hook outcome and failure message from a compose library

https://github.com/andrew-waters/orchard/issues/130

- State: open
- Opened by: @andrew-waters, 13 Oct 2026
- Parent: #126 Handle the new runHook operation from ComposePlanner (https://github.com/andrew-waters/orchard/issues/126)

## Description

Follow-up so Orchard can drop its copy of the hook rules. Move `HookOutcome`, `HookFailure`'s wording and the output bounding from `Sources/compose/Runtime.swift` into a library product (ComposePlanner or a small new one) that the plugin and Orchard both use, then release it. When it ships, open an Orchard issue to replace `ComposeHooks` with the package's version.

Independent of the Orchard tasks; not needed for R1-R11. Needs whoever looks after compose. Also worth publishing a GitHub release for 0.5.0, which only exists as a tag.

**Checked by:** the plugin's existing hook tests pass against the library version; the types are public in a library product; release notes mention them.

Planned in [Handle the new runHook operation from ComposePlanner](https://github.com/andrew-waters/orchard/blob/HEAD/plans/2026-10-13-handle-the-new-runhook-operation-from.md).

## Comments

### @andrew-waters, 26 Oct 2026 at 9:21

Planned in [Expose hook outcome and failure message from a compose library](https://github.com/andrew-waters/orchard/blob/HEAD/plans/2026-10-26-expose-hook-outcome-and-failure-message.md).

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

### Expose hook outcome and failure message from a compose library

Plan, in progress, about this issue: `plans/2026-10-26-expose-hook-outcome-and-failure-message.md` (https://github.com/andrew-waters/orchard/blob/main/plans/2026-10-26-expose-hook-outcome-and-failure-message.md)

Move the compose plugin's hook rules (what a failed hook means for the plan, how the failure reads, how much output is kept) into a library product, so Orchard can replace its ported ComposeHooks copy with the package's.

# Expose hook outcome and failure message from a compose library

Move the compose plugin's hook rules (what a failed hook means for the plan, how the failure reads, how much output is kept) into a library product, so Orchard can replace its ported ComposeHooks copy with the package's.

## Context

- Also looked at: you also have access to the compose repo, so create both PR's if necessary

## Requirement

In full in [requirements/expose-hook-outcome-and-failure-message.md](../requirements/expose-hook-outcome-and-failure-message.md).

**Problem:** The rules for what a failed post_start or pre_stop hook means (carry on or stop), how the failure reads, and how much output is kept live in the compose plugin's executable target, which nothing can import. Orchard ported them into Orchard/Services/ComposeHooks.swift, so there are two copies, and they have already drifted: Orchard keeps 5 output lines against the plugin's 20, words the advice differently, and reports runtime errors without the plugin's friendly() clean-up. Separately, Orchard attaches every container it creates with a bare hostname (its id), the bug compose 0.6.0 fixed in the plugin (compose#15): container's DNS matches fully qualified names with a trailing dot, so Orchard's containers are likely unreachable by name.

**Goal:** One copy of the hook rules, in a compose library product that both the plugin and Orchard use: whether a failed hook stops the plan or carries on, and the facts a failure message is built from. Each front end keeps its own wording.

**Who it's for:** Maintainers of compose and Orchard; indirectly, people whose compose files behave differently in Orchard and on the CLI when the copies drift. For the hostname fix: anyone whose containers in Orchard need to reach each other by name, compose projects especially.

**Scope:**

1. Move the hook outcome decision (carry on vs stop, driven by failureIsFatal) into a compose library product
2. Expose the facts each front end words a message from: the hook's name (phase, index, service), exit status or why it could not start, last output lines, how many later steps were not attempted, and the container left in place
3. Plugin and Orchard both use the library's version; Orchard drops its ported decision logic
4. Ship a line-bounding hook transcript in the library (append a line, last N lines, latest non-blank line) with the count set by the caller; the CLI keeps 20, Orchard keeps 5
5. Orchard bumps compose to the release carrying the library and swaps ComposeHooks for it in the same change, taking 0.6.0's DNS registration change with it
6. Fix Orchard's container hostname to be built as `container run` builds it (trailing dot, default domain when set), so containers resolve by name

**Out of scope:**

- Sharing exact message wording: the CLI and Orchard each word messages for their own surface
- Reading pipes, relaying output and draining backgrounded streams: these stay in each front end, which own their I/O
- A 0.5.x patch branch of compose
- Changing how hooks behave in either front end: same decisions, same wording as today
- Changing the hostname of containers that already exist: they pick up the fix when recreated

**Acceptance criteria:**

- **R1** When a caller passes a compose library a hook operation that failed (exited non-zero or could not start) and the number of later steps, the library shall return carry on or stop, decided by the hook's failureIsFatal.
- **R2** When the library describes a hook failure, it shall expose the facts a message is built from as public values: phase, index, service, container name, exit status or the start error, last output lines, and the number of later steps not attempted.
- **R3** When lines are appended to the library's hook transcript, it shall keep at most the caller's chosen number of most recent lines, and the most recent non-blank line.
- **R4** When the library product is built, it shall depend on nothing beyond compose's existing library dependencies (no apple/container or containerization).
- **R5** When a hook fails in the compose plugin, the plugin shall use the library's decision and transcript, and print the same messages and keep the same 20 lines as before (its existing hook tests pass).
- **R6** When compose releases the library change, the GitHub release notes shall name the new public hook types.
- **R7** When Orchard is built against that release, it shall use the library's decision and transcript, keeping only its own message wording in ComposeHooks.
- **R8** When a hook fails in an Orchard Compose run, the system shall behave as today: a failed pre_stop warns on its row and the plan carries on; a failed post_start fails the run, skips later steps and leaves the container; the message names the hook, its exit status or start error, and its last 5 lines.
- **R9** When Orchard ships the compose bump, the changelog shall name the compose version it takes, say hook rules now come from it with no change in behaviour, and say that containers reach each other by name once recreated.
- **R10** When Orchard creates a container, the system shall attach it with a hostname built as `container run` builds it: `<name>.` when the name has a dot, `<name>.<domain>.` when it has none and a DNS domain is set, and the bare name otherwise.
- **R11** When two containers created by Orchard share a network (a compose project's, for example), the system shall let one reach the other by its container name.

**Decisions:**

- What should the shared library own? **The decision and the facts: carry on vs stop, the hook's name, exit status or start failure, last output lines, later-step count, container left in place. Each front end words the message itself.**
- Who owns how many hook output lines are kept? **The library provides the bounding transcript; each caller sets the count (CLI 20, Orchard 5).**
- How should Orchard take the release carrying the library? **Bump to it in the same change that replaces ComposeHooks, taking 0.6.0's DNS registration with it; the changelog mentions it.**
- Are requirements R1-R9 right? **Approved as written.**
- R9 assumed the bump brings 0.6.0's DNS change into Orchard; it doesn't. How should R9 read? **Changelog names the version; and fix Orchard's own bare-hostname bug in this plan, with its own criteria (R10, R11) and task.**
- Are requirements R1-R11 right, including the hostname fix applying to every container Orchard creates? **Approved.**

## Design

**Order of work.** compose first (library change and release), then Orchard (bump and swap). The hostname fix in Orchard is independent and can land before or alongside.

**1. compose: hook rules into `ComposePlanner`.** Add `Sources/ComposePlanner/Hooks.swift` beside `HookOperation`, which already lives there; `ProjectIdentity` already imports Foundation, so no new dependency and no new product for Orchard to link (R4).
- `HookOutcome`: `.carryOn` or `.stop(laterSteps: Int, containerLeftInPlace: String)`, from `HookOperation.outcome(laterSteps:)`, driven by `failureIsFatal` (R1).
- `HookFailure: Error`: the hook, a reason (`.exited(Int32)` or `.couldNotStart(any Error)`), and `lastLines` (R2). No `description` wording; phase, index, service and container come from the public `HookOperation`.
- `HookTranscript`: thread-safe, `init(keeping: Int)`, `append(_:)`, `lastLines`, `latest` (most recent non-blank line) (R3).
- The plugin's `Runtime` keeps its wording, `friendly()`, and the pipe relay and 3s drain, built on the library transcript (keeping 20). Its existing hook tests keep passing; outcome and bounding cases move to `ComposePlannerTests` (R5).
- Release as 0.7.0 (new public API) with notes naming the types (R6).

**2. Orchard: bump to 0.7.0 and swap.** Pin `upToNextMinor` from 0.7.0. `ComposeHooks` shrinks to Orchard's wording: it renders the library's `HookOutcome` and `HookFailure` into today's exact messages and uses `HookTranscript(keeping: 5)`. `ComposeService.execute` and `runHook` switch to the library types; behaviour and text unchanged, pinned by the existing `ComposeTests` (R7, R8). Changelog entry (R9).

**3. Orchard: hostnames as `container run` builds them.** In `ContainerBackend.createContainer`, work out the domain once: `spec.dnsDomain` when set, else the daemon's `dns.domain` from the system config it already loads, as `container run` and the plugin do; compose containers need it since `ComposeService` passes an empty domain. That domain goes into both the resolver configuration and the hostname. Whether the default-nameserver rule (today keyed on `spec.dnsDomain`) should key on the effective domain is checked against `container run` in the task. A small pure `hostname(name:domain:)` (dot in name: `name.`; domain: `name.domain.`; else bare) feeds `AttachmentOptions`, unit-tested (R10). Manual check: a two-service compose project where one `wget`s or `nslookup`s the other by name (R11). Changelog line that existing containers pick it up when recreated (R9).

**Areas it touches:**

- `andrew-waters/compose` `Sources/compose/Runtime.swift#L82-L108`: HookOutcome and outcome(of:failingWith:later:) in the plugin's executable target: decides carry on (pre_stop) or stop (post_start) and builds CLI-worded messages using friendly(error).
- `andrew-waters/compose` `Sources/compose/Runtime.swift#L469-L540`: HookFailure (message with last output) and HookTranscript (keeps last 20 lines, relays to Output.line, drain with deadline). Transcript is coupled to FileHandle and the plugin's Output, so not all of it is library material.
- `andrew-waters/orchard` `Orchard/Services/ComposeHooks.swift`: Orchard's port: Outcome, name(of:), outcome(...), Failure, Transcript (5 lines, plus a latest line for live detail, no drain). Comment already points at #130 for its replacement.

**Patterns to follow:**

- `andrew-waters/orchard` `Orchard/Services/ComposeService.swift#L340-L372`: execute(_:) calls ComposeHooks.outcome and maps carryOn to a warned row plus alert, stop to a failed run with later steps skipped. The call site that would switch to the package's type.
- `andrew-waters/compose` `Package.swift`: Libraries ComposeModel, ComposeParser, ComposePlanner take only Yams; the container client stays in the executable on purpose. Anything moved into a library must not pull in apple/container.
- `andrew-waters/compose` `Sources/ComposePlanner/Operation.swift`: HookOperation (phase, index, service, containerName, command, failureIsFatal) is public in ComposePlanner, and ProjectIdentity already imports Foundation, so hook outcome types can sit beside it without a new dependency.
- `andrew-waters/compose` `Tests/ComposePluginTests/RuntimeTests.swift#L7-L150`: HookOutcomeTests and HookTranscriptTests use swift-testing with @testable import compose; the outcome and bounding cases move to ComposePlannerTests, relay and drain cases stay with the plugin.
- `andrew-waters/compose` `STANDARDS.md`: Harness standards for plans and requirements live in compose (with plans/_template.md); the Orchard harness has none, so the plan follows these.
- `andrew-waters/orchard` `Orchard/Services/ContainerBackend.swift#L516-L583`: createContainer already loads the container system config (loadContainerSystemConfig) and builds the DNS configuration from spec.dnsDomain; the hostname and the daemon-domain fallback belong here, in one place for every container.
- `andrew-waters/orchard` `Orchard/Services/DNSService.swift#L19-L26`: Orchard's own rule for a default domain: the one chosen in Orchard, else the daemon's dns.domain. The Run form fills spec.dnsDomain from it; compose does not.

**Risks:**

- `andrew-waters/compose` `Tests/ComposePluginTests/RuntimeTests.swift`: Hook outcome and transcript tests use @testable import compose; they would move to (or also run against) the library's test target.
- `andrew-waters/compose` `Sources/compose/Runtime.swift#L386-L437`: Between 0.5.0 and 0.6.0 the only source change is in the plugin's Runtime (DNS domain and trailing-dot hostname). The libraries Orchard links are unchanged, so bumping Orchard past 0.6.0 changes nothing for Orchard by itself.
- `andrew-waters/orchard` `Orchard/Services/ContainerBackend.swift#L581`: Orchard attaches containers with hostname: spec.id, a bare name: the same bug compose 0.6.0 fixed in the plugin (compose#15), so compose services in Orchard are likely unreachable by name in container's DNS. Not this plan's work; worth its own Orchard issue.
- `andrew-waters/orchard` `Orchard/Services/ComposeService.swift#L585`: Compose containers are created with dnsDomain "", so with R10 alone they would still get a bare hostname and R11 would fail. The plugin takes the daemon's dns.domain from config.toml; Orchard needs the same fallback.
- `andrew-waters/orchard` `Orchard/Services/ContainerBackend.swift#L581`: With no DNS domain anywhere, container run and the plugin both leave the hostname bare, so name resolution cannot work; R11 holds only when a domain is set.
- `andrew-waters/orchard` `Orchard/Services/ContainerBackend.swift#L521-L527`: Default nameservers are sent only when spec.dnsDomain is set. Once the daemon's domain fills in for an empty spec, containers that had no domain (all compose ones, Run-form ones with none) get a resolver domain too; check whether nameservers should follow, as container run does, so lookups do not change unexpectedly.

**Decisions:**

- Does R9's DNS clause hold? **Reopened: 0.6.0 only changes the plugin runtime, so the bump brings no DNS change to Orchard.**
- When a container spec has no DNS domain, which domain should its hostname and resolver use? **The daemon's dns.domain from config.toml, applied in ContainerBackend for every container, as container run and the compose plugin do.**
- Is the design right? **Approved: hook rules in ComposePlanner/Hooks.swift released as compose 0.7.0; Orchard bumps and keeps only its wording; hostnames built as container run builds them, with the daemon's dns.domain as fallback.**

## Tasks

1. [andrew-waters/orchard#148](https://github.com/andrew-waters/orchard/issues/148) Expose hook outcome, failure facts and a bounded transcript from ComposePlanner (satisfies R1, R2, R3, R4, R5, R6)
2. [andrew-waters/orchard#149](https://github.com/andrew-waters/orchard/issues/149) Take compose 0.7.0 and use its hook rules in place of the ported copy (satisfies R7, R8, R9)
3. [andrew-waters/orchard#150](https://github.com/andrew-waters/orchard/issues/150) Attach containers with a hostname container's DNS can find (satisfies R9, R10, R11)

**Decisions:**

- Are the three tasks right? **Approved as written.**

### Expose hook outcome and failure message from a compose library

Requirement, in progress, about this issue: `requirements/expose-hook-outcome-and-failure-message.md` (https://github.com/andrew-waters/orchard/blob/main/requirements/expose-hook-outcome-and-failure-message.md)

One copy of the hook rules, in a compose library product that both the plugin and Orchard use: whether a failed hook stops the plan or carries on, and the facts a failure message is built from. Each front end keeps its own wording.

# Expose hook outcome and failure message from a compose library

## Problem

The rules for what a failed post_start or pre_stop hook means (carry on or stop), how the failure reads, and how much output is kept live in the compose plugin's executable target, which nothing can import. Orchard ported them into Orchard/Services/ComposeHooks.swift, so there are two copies, and they have already drifted: Orchard keeps 5 output lines against the plugin's 20, words the advice differently, and reports runtime errors without the plugin's friendly() clean-up. Separately, Orchard attaches every container it creates with a bare hostname (its id), the bug compose 0.6.0 fixed in the plugin (compose#15): container's DNS matches fully qualified names with a trailing dot, so Orchard's containers are likely unreachable by name.

## Goal

One copy of the hook rules, in a compose library product that both the plugin and Orchard use: whether a failed hook stops the plan or carries on, and the facts a failure message is built from. Each front end keeps its own wording.

## Who it's for

Maintainers of compose and Orchard; indirectly, people whose compose files behave differently in Orchard and on the CLI when the copies drift. For the hostname fix: anyone whose containers in Orchard need to reach each other by name, compose projects especially.

## Requirements

1. Move the hook outcome decision (carry on vs stop, driven by failureIsFatal) into a compose library product
2. Expose the facts each front end words a message from: the hook's name (phase, index, service), exit status or why it could not start, last output lines, how many later steps were not attempted, and the container left in place
3. Plugin and Orchard both use the library's version; Orchard drops its ported decision logic
4. Ship a line-bounding hook transcript in the library (append a line, last N lines, latest non-blank line) with the count set by the caller; the CLI keeps 20, Orchard keeps 5
5. Orchard bumps compose to the release carrying the library and swaps ComposeHooks for it in the same change, taking 0.6.0's DNS registration change with it
6. Fix Orchard's container hostname to be built as `container run` builds it (trailing dot, default domain when set), so containers resolve by name

## Out of scope

- Sharing exact message wording: the CLI and Orchard each word messages for their own surface
- Reading pipes, relaying output and draining backgrounded streams: these stay in each front end, which own their I/O
- A 0.5.x patch branch of compose
- Changing how hooks behave in either front end: same decisions, same wording as today
- Changing the hostname of containers that already exist: they pick up the fix when recreated

## Acceptance criteria

- **R1** When a caller passes a compose library a hook operation that failed (exited non-zero or could not start) and the number of later steps, the library shall return carry on or stop, decided by the hook's failureIsFatal.
- **R2** When the library describes a hook failure, it shall expose the facts a message is built from as public values: phase, index, service, container name, exit status or the start error, last output lines, and the number of later steps not attempted.
- **R3** When lines are appended to the library's hook transcript, it shall keep at most the caller's chosen number of most recent lines, and the most recent non-blank line.
- **R4** When the library product is built, it shall depend on nothing beyond compose's existing library dependencies (no apple/container or containerization).
- **R5** When a hook fails in the compose plugin, the plugin shall use the library's decision and transcript, and print the same messages and keep the same 20 lines as before (its existing hook tests pass).
- **R6** When compose releases the library change, the GitHub release notes shall name the new public hook types.
- **R7** When Orchard is built against that release, it shall use the library's decision and transcript, keeping only its own message wording in ComposeHooks.
- **R8** When a hook fails in an Orchard Compose run, the system shall behave as today: a failed pre_stop warns on its row and the plan carries on; a failed post_start fails the run, skips later steps and leaves the container; the message names the hook, its exit status or start error, and its last 5 lines.
- **R9** When Orchard ships the compose bump, the changelog shall name the compose version it takes, say hook rules now come from it with no change in behaviour, and say that containers reach each other by name once recreated.
- **R10** When Orchard creates a container, the system shall attach it with a hostname built as `container run` builds it: `<name>.` when the name has a dot, `<name>.<domain>.` when it has none and a DNS domain is set, and the bare name otherwise.
- **R11** When two containers created by Orchard share a network (a compose project's, for example), the system shall let one reach the other by its container name.

Planned in [plans/2026-10-26-expose-hook-outcome-and-failure-message.md](../plans/2026-10-26-expose-hook-outcome-and-failure-message.md).

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/130-expose-hook-outcome-and-failure-message/`: give each repo it touches a worktree there, on the branch `130-expose-hook-outcome-and-failure-message`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/130-expose-hook-outcome-and-failure-message/<name>" -b 130-expose-hook-outcome-and-failure-message origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/130-expose-hook-outcome-and-failure-message/orchard" -b 130-expose-hook-outcome-and-failure-message origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/130-expose-hook-outcome-and-failure-message/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#130" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/130-expose-hook-outcome-and-failure-message/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#130]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/130-expose-hook-outcome-and-failure-message/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
