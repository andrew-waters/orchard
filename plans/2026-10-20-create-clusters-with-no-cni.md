---
type: plan
status: in-progress
summary: "Offer a three-way CNI choice when creating a cluster (kindnet, a manifest, or none via --cni NONE on container 1.6.0+), remember it for recreate, and show a cluster created with no CNI as waiting for one until a check inside the control plane sees every node Ready."
issues: [andrew-waters/orchard#135]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-20
---

# Create clusters with no CNI

apple/container 1.6.0 (apple/container#2277) lets `container k8s create --cni NONE` skip the CNI. The create then returns without waiting for the nodes to be Ready, since that needs a CNI, and the user installs their own with kubectl or Helm. Orchard only knew a cluster's containers were running, so such a cluster would read as Running while unusable.

## Design

- **Model.** `ClusterCNI` (`kindnet`, `manifest(path)`, `userInstalled`) replaces `cni: String?` on `create`, `recreate` and `ClusterRecreateSettings`. Not `none`, which reads as `Optional.none` wherever it is optional. `performCreate` passes `--cni NONE`, `--cni <path>` or nothing. `RememberedOptions` keeps `cni` for a path and adds `noCNI: Bool?`, so "none" is never taken for a path and older saved options still decode.
- **Version gate.** `ClusterService.supportsNoCNI(containerVersion:)`, 1.6.0 or later, sharing the comparison with `supportsWorkerNodes`.
- **Create sheet.** The CNI field under Advanced is a menu: Default (kindnet), Custom manifest (shows the file chooser; refused with no file) and None (install your own), the last only when supported. Each has its own caption; the docs link stays. A recreate remembered with no CNI on an install now below 1.6.0 falls back to kindnet and says so.
- **Waiting for a CNI.** `ClusterService.awaitingCNI` holds running clusters created with no CNI (as Orchard remembers) whose nodes aren't all Ready. A create with no CNI that succeeds enters it straight away. `refreshCNIReadiness(of:)` runs `container exec <control-plane> kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o json`, needing no kubectl or kubeconfig on the Mac, and `allNodesReady(kubectlNodesJSON:expectedNodes:)` parses it: Ready only when at least as many nodes as the cluster has are listed and every one has `Ready=True`. A failed check keeps the wait. Once Ready, a cluster isn't checked again (in memory; a relaunch checks once more). Delete and recreate reset it. Other clusters are never checked.
- **When it runs.** A `.task` loop on the Clusters list, every 10 seconds while it is on screen (it is beside a cluster's detail).
- **Presentation.** The list row reads "Waiting for CNI" with an orange icon; the detail's status dot is orange and an information banner (blue, not a warning) says to install a CNI with kubectl or Helm from Terminal (kubectl), with the docs link. A stopped cluster shows as stopped instead.
- **Out of scope:** clusters created with `--cni NONE` outside Orchard aren't tracked, to avoid regular `exec` calls against every cluster.

## Tasks

- [x] `ClusterService`: `ClusterCNI`, `--cni NONE`, `noCNI` in remembered options, `supportsNoCNI`, `awaitingCNI`, `refreshCNIReadiness(of:)`, `allNodesReady`
- [x] `CreateCluster.swift`: three-way CNI menu, gated; filled in when recreating, with the fallback note
- [x] `ListClusters.swift` and `ClusterDetail.swift`: readiness loop, "Waiting for CNI" row, banner and status dot
- [x] Tests in `ClusterServiceTests.swift`: `--cni NONE`; waiting on create, not on a failed one; remembered and passed on by recreate; the readiness parser; the check clears and stops, keeps the wait on failure, and skips other and stopped clusters; version gate
- [x] README, site clusters guide, CHANGELOG
- [x] App builds; OrchardTests pass (450 tests, 9 of them new; the whole unit target)
- [ ] Checked in the running app against container 1.6.0: create with None finishes promptly, shows waiting, applying a CNI clears it, recreate keeps None
