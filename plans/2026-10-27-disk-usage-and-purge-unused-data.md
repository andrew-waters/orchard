---
type: plan
status: done
summary: "Free Up Space from the Stats dashboard: a sheet that lists unused images (not used by any container, machines included), and opt-in stopped plain containers and unreferenced volumes, each with its size. It previews the total, asks for confirmation, then removes the chosen items and reports what it freed. In-use data is never listed."
issues: [andrew-waters/orchard#159]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-27
---

# Disk usage and purging unused data

## What is there already

The Stats dashboard shows Containers, Images, Volumes and Reclaimable tiles from `ClientDiskUsage.get()` (`container system df`), refreshed on a slow timer. That covers the usage view, so the work here is the purge. There is no way to reclaim space from Orchard today, other than trimming a running container's free blocks.

## What upstream offers (container 1.6.1)

The CLI's prune commands are loops over client calls Orchard already links:

- Images: `ClientImage.list()`, `ClientImage.delete(reference:garbageCollect: false)`, then `ClientImage.cleanUpOrphanedBlobs()`, which returns the digests deleted and the bytes freed.
- Containers: `ContainerClient.list(filters:)`, `diskUsage(id:)`, `delete(id:)`.
- Volumes: `ClientVolume.list()`, `volumeDiskUsage(name:)`, `delete(name:)`, with "in use" meaning that a container's configuration mounts the volume.

## What counts as unused

Every rule works from the full container list **including machine containers**, which `listContainers()` leaves out.

- **Images** (on by default): any image whose reference no container uses, running or stopped. This matches `container image prune -a`. The vminit and builder images are left out as well, because the runtime needs them.
- **Containers** (off by default): stopped containers that nothing else manages. A container is skipped when it has a `com.apple.container.plugin` label (machines, cluster nodes, builder), a compose project label, or is a sandbox. Removing one loses its writable layer.
- **Volumes** (off by default): volumes that no container mounts. Their contents cannot be recovered, and the sheet says so.
  - A volume is in use when a container's mount names it (`Mount.type.volume`, from #160). It is also in use when a mount's source path lies inside the volume's storage path. That covers containers that an Orchard before #160 recreated, which share the volume's disk image over virtiofs.
  - Volumes carrying a compose project label are never listed. After `compose down` they have no containers, but keeping them is the point (#162 owns removing them on down).
  - Once Volumes is turned on, anonymous volumes (`com.apple.container.resource.anonymous`) start ticked. Named volumes start unticked.

When containers are selected, images and volumes that only those containers used become unused too. The preview works this out and shows it, so what you see is what gets removed.

## Preview size

Each container and volume shows its own size from `diskUsage(id:)` and `volumeDiskUsage(name:)`. A single image's freed size isn't exact, because layers are shared. Each image shows its stored size, and the total is given as an estimate. The result screen then reports the exact bytes that `cleanUpOrphanedBlobs()` freed, plus the container and volume sizes.

## Where it lives

A "Free Up Space..." button in the Reclaimable tile on the Stats dashboard opens a sheet with:

1. A loading state while it builds the candidate list (sizes are fetched at the same time).
2. Three sections, Images, Containers and Volumes, each with a toggle, a checkbox and size for each item, and the section total. Containers and Volumes start off.
3. A footer with the total to free and a "Remove N Items..." button, which opens a confirmation listing the counts.
4. A progress state, then a result: items removed, space freed, and any items that failed with their errors. The sheet stays open for these, since an alert can't appear over a sheet.

Before removing anything, the purge reloads the container list and checks every candidate again. Anything that has come into use since the preview is skipped and reported, so a container started in between keeps its image and volumes. Images and volumes are decided again once the containers have gone, so a container that fails to go keeps what it uses.

Afterwards it refreshes disk usage, and the image and container lists.

## Dashboard tiles

After a purge, the runtime still calls the stopped builder and the vminit image reclaimable, so the Reclaimable tile kept showing space Free Up Space will never remove. The tiles now split the runtime's figures:

- A System tile holds the builder containers and the images the runtime needs (vminit and the builder image), which Containers and Images no longer count.
- Reclaimable is the most Free Up Space can remove with every section on: removable containers, the images and volumes left unused once they go, compose volumes excluded. Image sizes come from `ClientImage.calculateDiskUsage(activeReferences:)`, so shared layers count once.
- If the split can't be worked out, the tiles fall back to the runtime's own figures and System and Reclaimable show "--".

## Shape of the code

- `ContainerBackend`: `listAllContainers()` (machines included), `listVolumes()`, `volumeDiskUsage(name:)`, `containerDiskUsage(id:)`, `deleteVolume(name:)`, `cleanUpOrphanedBlobs() -> UInt64` and `systemImageReferences()` (vminit and builder). The existing `deleteImage` already skips GC, as the CLI's prune does, so the cleanup afterwards does it once; it also reclaims what earlier Orchard deletes left behind. The mock implements them all.
- An app-owned `ContainerVolume` model (name, size, format, created, labels, storage path, anonymous or not), shaped for #161's Volumes tab to reuse. The in-use rule ("which containers use this volume") is a function #161 can call too.
- #161's "Prune Volumes" should open this sheet with only volumes shown, so there is one set of rules for what is unused. I'll note this on #161.
- `Services/DiskPurge.swift`: pure functions that take containers, images and volumes and return the candidates, including the cascade when containers are selected. This is where the safety rules live, and it is unit tested. It also holds a `DiskPurgeService` that loads the plan, re-checks it and runs it.
- `Views/Features/Stats/FreeUpSpace.swift`: the sheet.
- Not in the command palette: `CommandPaletteCatalog` keeps destructive operations out on purpose.

## Out of scope

- Build cache (BuildKit) and Orchard's own files (stats history, build logs). File these as follow-ups if wanted.
- Dangling-only mode, and age-based rules ("not used in 30 days").
- A Disk Usage screen of its own, and a menu bar entry.

## Tasks

- [x] Backend: volume list, sizes and delete; container size; image delete without GC; orphaned blob cleanup; full container list; mock
- [x] `DiskPurge` candidate rules, with the cascade and the re-check before removal
- [x] `DiskPurgeService`: load, run and report
- [x] Purge sheet and dashboard button
- [x] Tests: rules (machines, compose, cluster, sandbox, builder and vminit are protected; volume in use by name and by path; compose volumes skipped; anonymous volumes ticked by default; cascade; re-check skips newly used items), service against the mock
- [x] Dashboard tiles: System tile, and Reclaimable as what Free Up Space can remove
- [x] README, site and CHANGELOG
- [x] One build and unit test pass (568 passed)
- [x] Manual check on 1.6.1: a pulled image no container uses is removed; a machine's image, a compose service and a cluster node are not listed; an unmounted volume is removed only when opted in; freed space matches the tile change
