---
type: plan
status: in-progress
summary: "A container's mounts keep their type through every recreate Orchard does (recovery, mount removal, Edit): named and anonymous volumes stay volumes with the same name, tmpfs stays tmpfs, block mounts stay block mounts, bind mounts stay virtiofs shares, each with all its options. The Mounts tab names the type in place of \"Unknown\". The form preserves these mounts but still only adds bind mounts."
issues: [andrew-waters/orchard#160]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-27
---

# Recreating a container keeps its volume and tmpfs mounts

Orchard read every mount as either tmpfs, virtiofs or "Unknown", and created every mount as a virtiofs share. A recreate (recovering an auto-removed container, removing a mount) turned a named volume into a virtiofs share of its backing image, and a tmpfs mount into a share of `tmpfs`. Edit was worse: its prefill skipped every mount that was not virtiofs, so Save & Recreate dropped volumes and tmpfs mounts altogether.

## What upstream does

- `Filesystem.FSType` has `.block(format:cache:sync:)`, `.volume(name:format:cache:sync:)`, `.virtiofs` and `.tmpfs`. A volume is also a block (`isBlock`), so the volume case is checked first.
- `container run -v name:/path` resolves the volume with `ClientVolume.create`, falling back to `ClientVolume.inspect`, and mounts `Filesystem.volume(name:format:source:destination:options:)` with the volume's format and backing path.
- Deleting a container leaves its volumes, anonymous ones included, so a delete-then-recreate can look the volume up again by name.

## What changes in Orchard

- `MountType` gains optional `volume` (name, format) and `block` (format). Optional keys, so stored snapshots and older JSON still decode. `mapFilesystem` maps all four types.
- `ContainerRunConfig.VolumeMapping` and `ContainerCreateSpec.Volume` gain a `kind`: bind, volume (name), tmpfs or block (format), bind by default. They carry the mount's options, not only `ro`.
- `createContainer` builds `.volume` (from `ClientVolume.inspect`), `.tmpfs`, `.block` or `.virtiofs` from the kind.
- One `VolumeMapping(mount:)` used by recovery, mount removal and Edit's prefill. Edit no longer drops mounts that aren't virtiofs.
- The form shows a row's kind. A volume row shows the volume name, and a tmpfs row has no source; the destination, read-only flag and delete still work. Add Volume still adds a bind mount.
- The Mounts tab, mount detail and Cmd+K name the type: Volume, Block, tmpfs or VirtioFS.

## Out of scope (follow-up to file)

- Creating named volumes and tmpfs mounts from the Run form, with a kind picker.

## Tasks

- [x] Model and mapping: volume and block mount types
- [x] Spec and create path: mount kinds, all options
- [x] Recovery, mount removal and Edit carry the kind
- [x] Form row and Mounts tab show the type
- [x] Tests: mapping for each type, spec round trip, Edit prefill
- [x] CHANGELOG
- [x] One build and unit test pass (556 passed)
- [ ] Manual: remove a bind mount from a container with `pgdata`, which stays mounted
