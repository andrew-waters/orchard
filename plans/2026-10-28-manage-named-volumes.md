---
type: plan
status: in-progress
summary: "A Volumes tab lists every volume with its size, format, creation date, labels and the containers that mount it, marks anonymous ones and filters for unused ones, creates volumes (name, size, labels) and deletes them, naming the containers that hold one in use. Prune Volumes opens Free Up Space with only its Volumes section. Each mount row in the run and edit forms picks bind mount, named volume or tmpfs, and a volume can be picked or created in place. Container detail links volume mounts to the volume, and image inspect lists the image's VOLUME declarations."
issues: [andrew-waters/orchard#161]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-28
---

# Manage named volumes

## What is there already

- #159 added `ContainerBackend.listVolumes()`, `volumeDiskUsage(name:)`, `deleteVolume(name:)` and `listAllContainers()` (machines included), the app-owned `ContainerVolume` model, and `DiskPurge.volume(_:isMountedBy:)`, which counts a volume as in use when a mount names it or shares a path inside its storage.
- #160 added `VolumeMapping.Kind` (bind, volume, tmpfs, block) and the create path for each, so a spec with a `.volume(name:)` row already mounts it. The form shows a kind but only adds bind mounts.
- Free Up Space (`FreeUpSpaceView`, `DiskPurgeService`) lists unused volumes with sizes, keeps compose volumes, ticks anonymous ones by default, re-checks before removing, and reports the result.

## What upstream offers (container 1.6.1)

- `ClientVolume.create(name:driver:driverOpts:labels:)`. `container volume create -s 10G` puts the size in `driverOpts["size"]`, so Orchard does the same.
- `ClientVolume.inspect`, `list`, `delete`, `volumeDiskUsage`. Deleting a mounted volume throws `VolumeError.volumeInUse(name)`.
- The image config type upstream decodes has no `Volumes`, so image inspect reads the config blob itself through `RemoteContentStoreClient().get(digest:)` and decodes only `config.Volumes`.

## Volumes tab

- `TabSelection.volumes` ("Volumes", `cylinder`), in the sidebar after Mounts, with list, detail and multi-select cards like Networks. The selection lives on `VolumeService`, as Compose keeps its selected project, rather than in more bindings threaded through the layout.
- `VolumeService` (environment object): `volumes`, `sizes` by name (`MeasuredSize`, read after the list), and `containers` from `listAllContainers()`, so a volume a machine mounts shows as in use. `users(of:)` is `DiskPurge.volume(_:isMountedBy:)` over those containers. Loaded with the rest and on the 5 second refresh, like networks; sizes are read for volumes not measured yet, and all again when the tab opens.
- List row: name, size, format; an "Anonymous" tag; a dot for in use. The list has an "Unused only" filter alongside search.
- Detail: name, size on disk, capacity when one was set, format, created, source path (copyable), labels, and the containers that mount it, each linking to the container. Buttons: Delete, and Run Container with this volume (opens Run with a volume row prefilled).
- Create sheet (`AddVolume`): name (validated as upstream does), optional size as entered for `-s` (`512M`, `10G`; checked against the same units), and label rows. `ContainerBackend.createVolume(name:size:labels:) -> ContainerVolume`, passing the size through as the CLI does.
- Delete, one or several, with a confirmation that warns the data can't be got back. Delete is disabled while any selected volume is mounted, and its tooltip names the volumes and the containers holding them. If the runtime still says `volumeInUse` (a container started in between), the error names the containers holding it from a fresh list.
- Prune Volumes: a toolbar button that opens Free Up Space with only the Volumes section, switched on. `FreeUpSpaceView(scope: .volumes)` hides the other sections and keeps images and containers out of the plan (`DiskPurgeSelection` with `includeImages = false`, so no image store clean-up either). One set of rules for unused.
- Dashboard: the Volumes tile is a button that opens the tab.
- Cmd+K: "Create Volume" and "Prune Volumes..." in Actions, and a Volumes section with each volume by name. Both actions open a sheet, so nothing destructive runs from the palette.

## Named volumes in the run and edit forms

- Each row has a kind picker: Bind Mount, Volume, tmpfs. Block rows from an existing container keep their read-only source, as now.
- Volume: a picker of existing volumes (with the anonymous ones under their own heading), plus "New Volume..." which opens the create sheet and selects what it made. The volume is created there and then, so a cancelled run leaves it behind; it shows in the tab and in Free Up Space like any unused volume.
- tmpfs: destination only.
- An incomplete row (no container path, or a volume row with no volume picked) is skipped, as an empty bind row already is; a volume row with none picked says so.
- "Add Volume" becomes "Add Mount", adding a bind row as now.

## Container detail

- The mounts list shows a volume mount by volume name with a link to it in the Volumes tab (`NavigateToVolume`, like networks). The Mounts tab keeps listing volume mounts, and a volume mount's detail links to the volume. `orchard://volume/<name>` links to one too.

## Image inspect

- Each variant's `volumes` comes from the config blob's `Volumes` keys, sorted. Nil when the blob can't be read, as for the other config fields.

## Shape of the code

- `ContainerBackend`: `createVolume`; the mock and `UITestSupport` implement it.
- `Services/VolumeService.swift` (with `VolumeUsage`, the pure in-use and delete rules), `Views/Features/Volumes/` (`ListVolumes`, `DetailVolume` with the multi-select cards, `AddVolume`), wiring in `Content`, `ThreeColumnLayout`, `DetailContent`, `MainInterface`, `AppServices`.
- `VolumeSize` parsing (`512M`, `10G`, `1T`, bytes) in `InputValidation`, unit tested.
- `FreeUpSpaceView` takes a scope.

## Out of scope

- Removing compose volumes on `compose down` (#162).
- Block mounts from the form, and tmpfs size options (the runtime takes none).
- Renaming or resizing a volume (the runtime can't).

## Tasks

- [x] Backend: create volume; image config `Volumes`; mock
- [x] `VolumeService`: list, sizes, users, create, delete with in-use check
- [x] Volumes tab: list with anonymous tag and unused filter, detail, multi-select, create sheet, delete
- [x] Free Up Space volumes-only scope, and Prune Volumes
- [x] Dashboard tile link and Cmd+K entries
- [x] Form: kind picker, volume picker, create in place, validation
- [x] Container detail links volume mounts
- [x] Tests: size parsing, users of a volume (by name, by path, machines), delete blocked while in use, scoped purge plan has no images, form rows to spec, image volumes decoding, palette entries
- [x] README, site and CHANGELOG
- [x] One build and unit test pass (582 passed)
- [ ] Manual check on 1.6.1: create a sized, labelled volume; run a container with it; Delete is off while it is mounted, naming the container; prune removes an anonymous volume only
