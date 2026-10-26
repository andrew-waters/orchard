---
type: requirement
status: in-progress
summary: "One copy of the hook rules, in a compose library product that both the plugin and Orchard use: whether a failed hook stops the plan or carries on, and the facts a failure message is built from. Each front end keeps its own wording."
issues: [andrew-waters/orchard#130]
plans: [plans/2026-10-26-expose-hook-outcome-and-failure-message.md]
---

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
