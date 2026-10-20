---
type: plan
status: in-progress
summary: "Build Orchard against apple/container 1.6.0 (containerization 0.52.1). Only machine creation needs a code change; 1.6.0 features are left to their own issues (#133-#136)."
issues: [andrew-waters/orchard#132]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-20
---

# Bump apple/container to 1.6.0

Orchard pins apple/container 1.5.0 and containerization 0.47.0. Every 1.6.0 feature issue (#133 commit, #134 DNS aliases, #135 clusters with no CNI, #136 machine user account) depends on building against 1.6.0 first.

## What changes between 1.5.0 and 1.6.0 for Orchard

From a diff of the two tags:

- **Machine API (apple/container#2322).** `MachineClient.machineConfigFromFlags` takes a new `user: Flags.MachineUser` and returns a `MachineConfiguration` instead of `(MachineConfiguration, MachineResources?)`. `MachineClient.create` no longer takes `resources:`, and `MachineResources` and `MachineKeys.machineResources` are gone. `UserSetup` gains a stored `home`. This breaks `LiveMachineBackend.createMachine`.
- **Name clash.** `MachineAPIClient` now has a `public enum MachineUserSetup` (the setup script). Orchard's own `struct MachineUserSetup` in `Models.swift` wins inside the Orchard module, so nothing needs renaming.
- **Network attachments (apple/container#2390).** `AttachmentOptions` gains `aliases: [String] = []` and decodes without it. Orchard's one call site compiles unchanged and Orchard decodes no attachments itself. Aliases in the UI are #134.
- **Builder and build (apple/container#2298, #2370).** `container build --progress plain` and `container builder status --format json` survive in the plugin. No change.
- **Clean-ups the release allows.** Nothing to remove: `fetchContainerLogs` already treats an empty log as no lines, and `listImages` and image load have no defensive handling for the cases 1.6.0 fixes.

## Over XPC with a 1.5.x runtime

A 1.6.0 client no longer sends `machineResources` (optional on 1.5.x) and adds `home` to `UserSetup` (ignored by 1.5.x's synthesised decoder; 1.6.0 falls back to `/home/<user>` when it is missing). Expected to keep working; confirmed by the smoke test below.

## Out of scope

- Choosing the machine's user, uid, gid and home: #136. Creation keeps the host-user defaults, as the CLI does without user options.
- Commit, DNS aliases and clusters with no CNI: #133, #134, #135.

## Tasks

- [x] Pin `container` at 1.6.0 in `project.pbxproj` and resolve `Package.resolved` (container 1.6.0, containerization 0.52.1; no other pins moved)
- [x] `MachineBackend.createMachine`: pass default `Flags.MachineUser`, drop `resources`
- [x] `supportedContainerVersion` to 1.6.0
- [x] App builds; OrchardTests pass (434 tests; the per-file filter matches nothing because the tests are free `@Test` functions, so the whole unit target ran)
- [ ] Smoke test on 1.5.x: create, start and stop a container and a machine; build an image; builder status; logs on a silent container
- [ ] Smoke test on 1.6.0: the same
- [x] README requirements and CHANGELOG
