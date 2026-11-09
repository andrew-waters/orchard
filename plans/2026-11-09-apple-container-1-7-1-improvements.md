---
type: plan
status: done
summary: "Bring Orchard in line with Apple container 1.7.1: size worker nodes apart from the control plane, read each cluster's stored configuration from `cluster ls --format json`, report an out-of-date kernel against the running version's recommended one, and offer to leave snapshots/ and containers/ out of Time Machine. Builds on #176."
issues: [andrew-waters/orchard#174]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-11-09
---

# Apple container 1.7.1: improvements

Builds on #176 (`173-support-apple-container-1-7-1-must`), which moves Orchard to container 1.7.1. This branch starts from that one and is rebased onto `main` once #176 merges. Parts 1 to 3 are gated so 1.6.x behaves as it does today. Part 4 shows on every version, since `snapshots/` and `containers/` are rebuildable on all of them (agreed 2026-11-09).

Upstream facts, read from the 1.7.1 tag:

- `--workers` takes a plain count or `count=<n>,cpus=<n>,memory=<size>` and can be repeated (`WorkerGroup.init(parsing:)`). A group's count defaults to 1; cpus and memory left out get the single-node defaults (a quarter of the host, at least 2 CPUs and 2g). `--cpus`/`--memory` size the control plane only.
- `cluster ls --format json` prints `[ClusterResource]`: `{id, configuration: {name, kubernetesVersion, cni, fqdn, remove, sharedImageStore, nodes: [{name, kind, roles}], creationDate, labels}, status}`, dates as ISO 8601. `cni` is the manifest path, `NONE`, or null for kindnet.
- The recommended kernel is `kernel.binaryPath` in `container system property list --format json` (1.7.1: `opt/kata/share/kata-containers/vmlinux-6.18.56-208-debug`). The installed kernel is the target of `kernels/default.kernel-<arch>`.
- #2412 sets `isExcludedFromBackup` (the sticky exclusion `tmutil addexclusion` sets) on `snapshots/` and `containers/` only when it creates them.

## 1. Size worker nodes separately

- [x] `ClusterWorkerGroup { count, cpus: Int?, memoryGiB: Int? }` in `ClusterService`. `performCreate` takes `[ClusterWorkerGroup]`: a group with no size is `--workers <n>`, a sized one `--workers count=<n>,cpus=<n>,memory=<n>GB`. Below 1.7 only the plain form is sent (sizes dropped), and a pure `nonisolated static func workerArguments(_:containerVersion:)` builds them for tests.
- [x] `supportsWorkerSizing(containerVersion:)`: `>= 1.7`.
- [x] Create Cluster (1.7+): the resources fields are labelled as the control plane's once workers > 0, and a **Worker size** override (CPUs, memory) appears under the worker count. Off says what an unsized worker gets: a quarter of the Mac's CPUs and memory, at least 2 CPUs and 2 GB. Below 1.7 the form is unchanged and says workers match the control plane.
- [x] Remembered options gain the worker size (optional fields, so older saved options still decode).
- [x] `ClusterRecreateSettings.workerGroups`: read from the live worker containers, grouped by (CPUs, memory), else from the remembered options. More than one group (made with the CLI) is kept: Recreate sends every group and shows them as a read-only summary (agreed 2026-11-09).
- [x] Tests: argument building on 1.6.1 and 1.7.1 (plain, sized, several groups), recreate from live workers, from remembered options, and from mixed sizes.

## 2. Read cluster details from the clusters service

- [x] `StoredClusterConfiguration` (own small `Decodable`, not upstream's type, so a field upstream adds or validates differently can't fail the decode), parsed by a pure `parseClusterList(json:)`.
- [x] `ClusterService.storedConfigurations: [String: StoredClusterConfiguration]`, refreshed on 1.7+ when the Clusters tab appears, after create, delete and recreate, and with the plugin probe. Only the newest load applies. A failed run or bad JSON empties it, leaves `storedConfigurationsLoaded` false and logs, as does a system stop; below 1.7 it stays empty.
- [x] `K8sCluster` gains `stored: StoredClusterConfiguration?`; `K8sCluster.group(containers:stored:)` attaches it by name. Node state still comes from the snapshot. A stored cluster with no node containers is listed with no nodes, so it can be deleted or recreated, as the CLI lists it (agreed 2026-11-09).
- [x] The list and detail show the Kubernetes version and creation date when known. On 1.7+, a cluster with no stored configuration shows a short note: made before Apple container 1.7, so `container cluster ls` doesn't list it; Delete still works.
- [x] Recreate takes the CNI and Kubernetes version (as `kindest/node:<version>` when the image isn't otherwise known) from the stored configuration first, then the remembered options.
- [x] Tests: parsing (kindnet, manifest, NONE, missing optional fields, garbage), merging with the snapshot grouping, recreate preferring stored over remembered.

## 3. Report the recommended kernel accurately

- [x] `KernelStatus`: `.recommended`, `.outdated(installed:recommended:)`, `.custom`, `.notInstalled`, `.unknown`. A pure `KernelStatus.compare(installedTarget:recommendedBinaryPath:)` compares file names. A Kata build name (`vmlinux-<version>-<build>[-debug]`) that isn't the recommended one is outdated; anything else is custom. With no recommended path (property list failed), today's behaviour stands.
- [x] `loadKernelStatus` reads `kernel.binaryPath` from the system properties, and runs after every `loadSystemProperties`.
- [x] Settings: outdated shows both versions and **Use recommended kernel**, which calls the existing `setRecommendedKernel()`. Custom stays custom, unflagged.
- [x] Tests: recommended, outdated (the 1.6.1 kernel `vmlinux-6.18.35-197-debug` against 1.7.1), custom, and no recommended path.

## 4. Leave rebuildable data out of Time Machine

- [x] `BackupExclusion` service: reads `isExcludedFromBackup` on `<app root>/snapshots` and `<app root>/containers`, and sets it on both on request. Never touches `volumes/`.
- [x] Settings > System, on every version: a **Time Machine** row with the state of both, a **Leave out of backups** button when either is included, and why it's safe (they're rebuilt by pulling the image or recreating the container; volumes stay backed up). The state is read again after the action.
- [x] No alert, badge or prompt: the row only shows in Settings, so someone who put the folders back in their backups isn't nagged.
- [x] Tests on a temp directory: read, exclude, `volumes/` untouched.

## 5. Retest builds on 1.7.1

- [x] Manual, by Andrew: Images tab builds on 1.7.1, a multi-stage one and one copying the whole context; retest and close or update open build issues. No code change. Retested 2026-11-09: a two-stage build whose first stage copies the whole context (nested files and `.dockerignore` checked inside the build) built and ran correctly. No open Orchard issues about build failures.

## Docs

- [x] CHANGELOG (Added/Changed), README and `site/clusters.html`: worker sizing, cluster details from the clusters service, kernel status, Time Machine. Drop "each worker gets the same CPUs and memory as the control plane" for 1.7.1.
