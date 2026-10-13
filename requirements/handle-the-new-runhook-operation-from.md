---
type: requirement
status: in-progress
summary: "Orchard's Compose tab runs post_start and pre_stop hooks as the compose file declares them, so a project behaves the same in Orchard as with the compose plugin."
issues: [andrew-waters/orchard#126]
plans: [plans/2026-10-13-handle-the-new-runhook-operation-from.md]
---

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
