---
type: plan
status: in-progress
summary: "Move the compose plugin's hook rules (what a failed hook means for the plan, how the failure reads, how much output is kept) into a library product, so Orchard can replace its ported ComposeHooks copy with the package's."
issues: [andrew-waters/orchard#130, andrew-waters/orchard#148, andrew-waters/orchard#149, andrew-waters/orchard#150]
touches: [andrew-waters/compose, andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-26
requirement: requirements/expose-hook-outcome-and-failure-message.md
---

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
