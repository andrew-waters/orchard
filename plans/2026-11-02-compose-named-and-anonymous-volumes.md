---
type: plan
status: agreed
summary: "Compose projects create and mount their named and anonymous volumes (andrew-waters/orchard#162), on compose 0.8.0: the plan's volume operations run through ContainerBackend, mounts map onto volume mounts, the project detail lists its volumes, and Down offers to remove them, defaulting to keep."
issues: [andrew-waters/orchard#162]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-11-02
---

# Compose named and anonymous volumes

A compose file's named and anonymous volumes are created and mounted when Orchard brings a project up, and survive `down` unless the user chooses to remove them. The compose half shipped in andrew-waters/compose#19, released as compose 0.8.0.

## What compose 0.8.0 gives us

- `CreateOperation.Mount.source`: `.bind(path)`, `.namedVolume(name)`, `.anonymousVolume(name)`, every name already resolved. `hostPath` is gone.
- `Operation.createVolume` and `.removeVolume`, each a `VolumeOperation(name:labels:)`.
- `CurrentState.volumes` (`VolumeState`: name, labels) and `ContainerState.volumes`, the volume names a container mounts. The planner uses the second to refuse a volume a running container outside the project holds (`PlanError.volumeInUse`) and to keep a volume something else still mounts on `down -v`.
- `DownOptions(removeVolumes:)`, default false; it removes only volumes labelled with the project.
- Anonymous volumes are named `<project>_<service>_<12 hex of the target's SHA-256>` and labelled with the runtime's anonymous label, project, service and target, so a recreate reuses them, as does an `up` after a plain `down`.
- New `PlanError`s (`missingExternalVolume`, `sharedVolume`, `volumeInUse`) need nothing: Orchard already shows a plan error's description.
- A service that mounts a volume hashes differently from 0.7.0, so it is recreated once on its first `up` after the upgrade. That recreate is what attaches the volume.

## Design

- **Pin**: the compose package to 0.8.0 in `project.pbxproj` and `Package.resolved`, and `ComposePluginService.linkedVersion` with it (a test holds the two together).
- **Snapshot** (`ComposeService.snapshot`): also `backend.listVolumes()` into `VolumeState`. `containerState(of:)` fills `volumes` from the container's volume mounts (`mount.type.volume?.name`).
- **Running operations**: `.createVolume` calls `backend.createVolume(name:size: nil, labels:)`, `.removeVolume` calls `backend.deleteVolume(name:)`. Their rows carry a new `ComposeRun.Step.volume`, as network rows carry `network`.
- **Create spec**: `createSpec(from:)` maps `.bind` to a bind `VolumeMapping` and both volume kinds to `.volume(name:)`, which `createContainer` already mounts (#160). `ensureBindSources` only looks at bind mounts.
- **After a run**: a `reloadVolumes` hook, like `reloadNetworks`, refreshes `VolumeService`.
- **Project detail**: a Volumes table under Networks (`VolumeTable`, shaped like `NetworkTable`): the volumes the file declares and the anonymous ones its services mount, plus any volume labelled with the project. Each row shows its kind (named, anonymous, external), size, and status, which is what the run is doing to it or whether a container mounts it; one not created yet is a placeholder. A row opens the volume in the Volumes tab.
- **Down**: in the detail and the list's context menu. When the project has volumes labelled with it, a confirmation lists them, with **Keep Volumes** as the default and **Remove Volumes** as the destructive choice; with none, Down runs as now. `ComposeService.down(project:removeVolumes:)` passes it to `DownOptions`.

**Decisions:**

- Anonymous volumes? **Deterministic and labelled, decided in compose#19.**
- How Down offers removal? **A confirmation only when the project has volumes, defaulting to keep.**

## Out of scope

- Volume `driver_opts` (compose notes them), and image `VOLUME` declarations becoming anonymous volumes.

## Tasks

- [x] Pin compose 0.8.0 and `linkedVersion`
- [x] Snapshot volumes and each container's volume mounts
- [x] Volume operations, rows and `reloadVolumes`
- [x] Mount kinds in `createSpec`; bind-only `ensureBindSources`
- [x] Project detail Volumes table
- [x] Down confirmation in the detail and the context menu
- [x] Tests: mount mapping, volume step rows, bind-only sources, container volume names, down options
- [x] README and CHANGELOG (compose 0.8.0, the one-off recreate)
- [x] One build and unit test pass (592 passed)
- [ ] Manual check: a `postgres` service on a named volume keeps its data across Down (Keep Volumes) and Up, and loses it with Remove Volumes
