---
type: plan
status: done
summary: "Offer worker nodes when creating a cluster (container k8s create --workers) and a node picker when loading an image (--node), both only on container 1.6.0 or later. Adding a node to a running cluster stays out of scope."
issues: [andrew-waters/orchard#87]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-20
---

# Create clusters with worker nodes

apple/container 1.6.0 (apple/container#2276) lets `container k8s create` make worker nodes, but only at create time. Orchard already groups `<cluster>-worker-N` nodes under their control plane; what is missing is a way to ask for them, a way to target them when loading an image, and copy that stops saying workers can't exist.

## What 1.6.0 does (from the plugin source at the `1.6.0` tag)

- **`--workers <n>`** (`UInt`, default `0`, at most 1024). With `0` the single node is labelled `control-plane,worker` and left schedulable, as before. With `n > 0` the control plane is labelled `control-plane` alone and stays tainted, so workloads run only on the workers, which are labelled `worker` and named `<cluster>-worker-1` upwards. Every worker gets the same `--cpus` and `--memory` as the control plane. A create that fails partway tears down the workers it made.
- **`k8s delete`** removes the workers too (found by the `worker` label and the `<cluster>-worker-` prefix).
- **`k8s load-image --node <name>`** (repeatable) loads into the named nodes only; each must be the control plane or one of its workers, or the command fails. Without it, every node gets the image.
- **List grouping (apple/container#2315)** splits the role label on commas and treats any node whose roles include `control-plane` as the control plane. `K8sCluster.group` already does exactly this (it was fixed in Orchard for the 1.4.1 `control-plane,worker` label, and has tests for a combined-role control plane with and without workers). No code change; one more test for the 1.6.0 shape.
- **Version:** `SystemHealthInfo.apiServerVersion` is `ReleaseVersion.version()`, a plain `1.6.0`. Orchard still runs against a 1.5.x runtime, so the controls are gated on it.

## Design

- **Version gate.** A pure `ClusterService.supportsWorkerNodes(containerVersion:)` that compares the dotted numbers against `1.6.0` (anything unparseable, or nil while the system is stopped, is `false`). Views read `systemService.containerVersion` from the environment and ask it. No new dependency between services.
- **Create sheet.** A "Workers" `NumericStepperField` under Advanced, above the CNI field, default `0`, shown only when supported. Its range is upstream's own limit, `0...1024` (`K8sCluster.maxWorkers`): any count can be typed or stepped, so there is no Orchard cap to revisit. Caption: with 0 the control plane also runs workloads; with more, workloads run only on the workers, each a node with the same CPUs and memory, and each adds to the create time. Advanced opens by itself when recreating a cluster that had workers.
- **ClusterService.** `create` and `recreate` take `workers: Int = 0`; `performCreate` appends `--workers <n>` only when `n > 0`, so a pre-1.6.0 install never sees the flag. `RememberedOptions` gains an optional `workers` (old saved entries still decode). `ClusterRecreateSettings` gains `workers`: the number of worker nodes the cluster has now, else the remembered value when no workers are listed. Unlike the image and CNI the count can be read off the cluster, so a remembered one gone stale after a delete and create outside Orchard does not win.
- **Load Image sheet.** When supported and the cluster has more than one node: a "Nodes" choice of "All nodes" (default) or "Selected nodes", the latter listing each node with a checkbox and its role. Load is disabled while "Selected nodes" has none ticked. `loadImage(cluster:reference:nodes:)` passes one `--node` per selected node, and nothing when "All nodes" is chosen. The sheet takes the cluster's node ids and roles from `ClusterDetailView`.
- **Single-node banner** (`ClusterDetail.swift`). Kept for pre-1.6.0 installs, reworded to say Apple container 1.6.0 adds worker nodes at create time. Hidden on 1.6.0 and later, where a single node is a choice rather than a ceiling.
- **Clusters list** (added after review of the running app). A cluster with more than one node gets a chevron, and its nodes are listed under it when expanded. Selecting a node shows its container's detail in the right-hand panel; the selected node is held as `ClusterService.selectedNode`, like `ComposeService.selectedProject`, with the expanded clusters beside it so a tab switch can't hide the selection, and goes back to the cluster on collapse, when the node goes, or when something else selects a cluster. Left and right arrows expand, collapse and step between a cluster and its nodes, as in Finder.
- **Out of scope:** adding a node to an existing cluster (no upstream command; we don't reimplement kubeadm join, as with #71 and #51).

## Tasks

- [x] `ClusterService`: `supportsWorkerNodes(containerVersion:)`; `workers` on `create`, `recreate`, `performCreate`, `RememberedOptions` and `ClusterRecreateSettings`; `nodes` on `loadImage`
- [x] `CreateCluster.swift`: Workers stepper under Advanced, gated; filled in when recreating
- [x] `ClusterDetail.swift`: node picker in `LoadImageSheet`, gated; version-gate and reword the single-node banner
- [x] Tests in `ClusterServiceTests.swift`: `--workers` passed only when above 0; `--node` per selected node and none for all; remembered and derived worker counts in recreate settings; old remembered options without `workers` still decode; version comparison (1.5.0, 1.5.10, 1.6.0, 1.10.0, 2.0, garbage, nil); grouping of a 1.6.0 cluster (`control-plane` plus two `worker` nodes)
- [x] App builds; OrchardTests pass (441 tests, 7 of them new; run as the whole unit target, since the tests are free `@Test` functions)
- [x] Clusters list: expandable node rows, node selection drives the detail, left and right arrows
- [x] Checked on 1.6.0 (create, load-image and delete run with the arguments Orchard builds; the result viewed in the app): a cluster with 2 workers shows three nodes with the right roles; deleting it removes all three containers; loading an image into one worker puts it there only (`crictl images` on each node). Done: the list showed control-plane, worker, worker; `crictl images` found the image on `k8s-dev-worker-1` only; `k8s list` and `container list --all` were empty after the delete. On 1.5.x neither control shows: covered by the version tests, not run against a 1.5.x install
- [x] README Clusters section, `site/clusters.html` (replace "Single-node clusters (for now)"), CHANGELOG entry
