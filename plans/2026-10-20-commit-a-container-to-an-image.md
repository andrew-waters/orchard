---
type: plan
status: in-progress
summary: "Commit a container to an image on container 1.6.0+: export the filesystem over XPC, build the OCI image archive in Orchard the way upstream's internal OCIImageArchive does, and load it into the image store. A Commit to Image sheet from the detail header, list context menu and Cmd+K, asking before it replaces an existing image, and linking to the new image when done."
issues: [andrew-waters/orchard#133]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-20
---

# Commit a container to an image

apple/container 1.6.0 adds `container commit <id> <reference>` (apple/container#1762). Orchard builds against 1.6.0 since #132 and already exports a container as a tar; commit sits beside it.

## What upstream does

At the `1.6.0` tag, `ContainerCommit.run()` is all client side; there is no new XPC route:

1. `ClientImage.normalizeReference` on the reference (so `web:latest` becomes `docker.io/library/web:latest`).
2. `ContainerClient().get(id:)` for the snapshot, and the source image's config for the container's platform.
3. `ContainerClient().export(id:archive:)` writes the rootfs as a tar. On a running container the daemon snapshots it first, as for Export.
4. `OCIImageArchive.create` wraps that tar as a one-layer OCI layout (layer blob, config, manifest annotated with the reference, `index.json`) and archives it with `ArchiveWriter`.
5. `ImageLoad.load` calls `ClientImage.load(from:)` and unpacks each loaded image.

`OCIImageArchive` and `ImageLoad.load` are internal to `ContainerCommands`, which Orchard doesn't link. Everything they call is public in products Orchard already reaches: `ContainerClient`, `ClientImage` (ContainerAPIClient), `ContentWriter` and the OCI types (ContainerizationOCI), `ArchiveWriter` (ContainerizationArchive, a dependency of ContainerAPIClient). So Orchard takes the preferred route: drive the XPC export and load itself, with a port of `OCIImageArchive.create` (about 60 lines). No shelling out to `container commit`.

### What the image inherits

Not just the filesystem. Upstream writes an image config from the container, not the source image:

- **From the container's init process:** user, environment, working directory, and the command, as `entrypoint: [executable]` and `cmd: arguments`. So a container started from `ENTRYPOINT ["nginx"] CMD ["-g", "daemon off;"]` commits with the same full command line, but split differently: overriding the command at run time replaces the arguments only.
- **Stop signal** from the container's configuration.
- **Labels:** the source image's, with the container's on top.
- **From the source image:** author, OS version and features. Architecture, OS and variant come from the container's platform.
- **Not carried:** exposed ports, volumes, healthcheck, and the source image's layer history. The image is a single flattened layer.

The sheet says this in one caption, rather than "filesystem only".

## Replacing an existing reference

Loading an image under a reference that already exists moves the reference to the new image (`ReferenceManager.create` sets `state[reference] = descriptor`), so `container commit` silently replaces it. Orchard **asks first**: when the normalised reference matches an image in `ImageService.images`, the sheet shows "An image named <reference> already exists" under the field and the button reads **Replace Image**, with a confirmation alert. The old image's tag moves; containers already created from it keep running, because their rootfs is a copy. Its blobs are left for Prune, as the CLI leaves them.

## Orchard changes

- **Backend** (`ContainerBackend.swift`): `commitContainer(id:reference:onPhase:) async throws -> String`, returning the stored reference so the UI links to what was actually loaded. The live implementation follows the steps above in a scratch directory removed on exit, and reports phases ("Exporting filesystem", "Building image", "Loading image") for the sheet. The archive building goes in a new `Orchard/Services/ContainerCommit.swift`, with the image-config mapping as a pure function so it can be unit tested.
- **Service** (`ContainerListService`): `commitContainer(_:to:)` with `committingContainers: Set<String>` and the current phase per container, matching `exportingContainers`; refreshes images after a commit; errors through `AlertCenter`. `static func supportsCommit(containerVersion:)` (1.6+), like `MachineService.supportsUserAccount`.
- **Validation:** move the build sheet's image-name regex out of `ImageBuildService.validationError` into `InputValidation.isValidImageReference`, used by both sheets, so they validate identically.
- **Sheet** (`Containers/CommitContainer.swift`): reference field prefilled with `<container-name>:latest`, the inheritance caption, a note on running containers being snapshotted, the replace warning, progress while it runs, and on success "Committed <reference>" with **View Image** (opens `orchard://image/<reference>`) and **Run Image**, as finished builds do. Closing the sheet mid-commit leaves it running; the header shows "Committing…".
- **Entry points**, all only when `supportsCommit` is true:
  - `ContainerDetailHeader`: "Commit…" beside "Export…", with "Committing…" while in flight.
  - `ListContainers` context menu: "Commit to Image…" beside "Export Filesystem…" (single selection).
  - Cmd+K: a `Commit: <id>` entry per container (`keywords: "commit snapshot save image"`, so "commit web" finds it), firing a new `PaletteAction.showCommitContainerSheet(String)`. `CommandPaletteCatalog.entries` gains a `supportsCommit` argument.
- **Test doubles:** `UITestSupport` and `OrchardTests/Mocks.swift` get `commitContainer`, next to `exportContainer`.
- **Docs:** README Orchard Features ("export as tar, commit to an image"), the site's Containers card, CHANGELOG under Unreleased/Added.

## Out of scope

- Commit options upstream doesn't have yet (author, message, changes, pause).
- Squash or multi-layer commits.

## Version gate

Offered on container 1.6.0 or later, as the issue asks. The work is client side over the export and load routes, so it may also work against a 1.5.x runtime, but 1.6.0 is what upstream ships and tests commit with.

## Tasks

- [x] Confirm how the image store treats an existing reference on load (it replaces it)
- [ ] `ContainerCommit.swift`: OCI archive and image-config mapping; backend `commitContainer`
- [ ] `ContainerListService.commitContainer`, in-flight state, `supportsCommit`
- [ ] `InputValidation.isValidImageReference`, shared with the build sheet
- [ ] Commit sheet, detail header button, context menu item
- [ ] Palette entry and `showCommitContainerSheet` handling in `ContentView`
- [ ] `UITestSupport` and `Mocks` doubles; unit tests for the service, validation, config mapping and palette entry
- [ ] README, site, CHANGELOG
- [ ] Checked on 1.6.0: commit a running and a stopped container; both appear in Images; running the image shows the changed files; committing to an existing reference asks, then replaces it
