---
type: plan
status: in-progress
summary: "Container 1.6.1 renamed the k8s plugin to cluster. Pick the subcommand from the installed version in one place, treat nodes labelled either cluster or k8s as cluster nodes, and keep clusters made before the upgrade listable, deletable and recreatable by deleting their nodes directly, with load image and write config disabled for them. Also builds against and installs 1.6.1 (#152)."
issues: [andrew-waters/orchard#146, andrew-waters/orchard#152]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-26
---

# Support container 1.6.1's rename of the k8s plugin to cluster

apple/container 1.6.1 renames the Kubernetes plugin from `k8s` to `cluster` (apple/container#2427). The subcommand, the node label, the plugin's state directory and its default cluster name all moved. Orchard hard-codes `k8s` for the first two, so on 1.6.1 the Clusters tab says the plugin is missing, and new nodes show as loose containers.

## What happens today

- `ClusterService` runs `["k8s", ...]` for the probe, `create --help`, create, delete, recreate's delete, `load-image` and `write-config`. On 1.6.1 the probe gets `unknown command 'k8s'` and sets `.missingPlugin`.
- `K8sCluster.pluginName = "k8s"` decides grouping (`group`, `clusterName(for:)`) and `Container.isK8sNode`, which swaps Start for Recreate and keeps nodes out of bulk Start.
- `ClusterService` has no view of the container version; views pass `systemService.containerVersion` into its static `supports*` checks.
- Nothing in Orchard reads the plugin's state directory. The Create Cluster sheet always passes `--name`, so the default name moving changes nothing that breaks; the field's placeholder and initial value say `k8s-dev`.

## Approach

### One place decides the command

- `ClusterService.pluginCommand(containerVersion:) -> String`, `nonisolated static`: `"cluster"` when `isContainerVersion(_, atLeast: [1, 6, 1])`, else `"k8s"`. Nil or unparseable gives `k8s`, like the other gates (the probe then fails as a stopped system and stays `.unknown`).
- `ClusterService` gets a `containerVersion: @MainActor () -> String?` hook, wired in `AppServices` to `systemService.containerVersion` like `existingContainerIDs`. Every CLI call builds its arguments from `[command] + [...]`, so no call site spells the plugin name.
- The probe treats `unknown command '<command>'` as missing for whichever command it ran, keeping the 1.4.1 "plugin ... not found" match.

### Both labels are cluster nodes

- `K8sCluster.pluginNames = ["cluster", "k8s"]` replaces `pluginName`. `group`, `clusterName(for:)` and `isK8sNode` match either. The badge keeps showing the raw label, so a legacy node reads "k8s · control-plane" and a new one "cluster · control-plane".
- `K8sCluster.isLegacy`: every node is labelled `k8s`. A cluster is **stranded** when it is legacy and the command is `cluster` (`ClusterService.isStranded(_:)`). On 1.6.0 and earlier nothing is stranded and nothing changes.

### Stranded clusters

- **Delete**: `container delete --force <every node id>` through the runner instead of `cluster delete`, then the same bookkeeping as today (forget remembered options, CNI generation, reload). The old plugin's state under `plugins/k8s` and any kubeconfig context are left behind; upstream's delete would have removed its own state, but Orchard has no business in the plugin's directory. Noted in the guide.
- **Recreate**: the same direct delete, then `cluster create` with the recreate settings, so the cluster comes back under the new label.
- **Load image** and **Write kubeconfig**: disabled, with help text saying the cluster was made by an older Apple container and Recreate brings it under the cluster plugin. Open Terminal (only `kubectl config use-context`) stays.
- **Cluster detail**: a notice above the nodes saying the same, with a Recreate button, shown only for stranded clusters. The delete confirmation for a stranded cluster says its node containers will be deleted directly.

### Copy

- "the `k8s` plugin" becomes "Apple container's cluster plugin" in `ListClusters` (missing-plugin state), `CreateCluster` (node image caption, CNI caption) and `ClusterDetail` (workers notice), whatever the version. Doc comments that name the command say `cluster` (formerly `k8s`) where they describe it.
- The Create Cluster sheet's default name follows upstream: `cluster-dev` on 1.6.1, `k8s-dev` before.
- The sidebar tab is **Clusters**, not "k8s Clusters", matching upstream's naming. The command palette still finds it by "k8s" and "kubernetes".

### Docs

- README Clusters section and comparison footnote, `site/clusters.html`, and a CHANGELOG entry under Unreleased > Fixed.

### Build against 1.6.1 (#152, folded in)

- Package pin to 1.6.1, which moves containerization to 0.53.0. Nothing Orchard calls changed shape.
- `supportedContainerVersion` to 1.6.1, so **Install container** fetches the 1.6.1 package, which is signed by the same team the install checks for.
- The Compose hook runner kills its process when the wait fails, now that the 1.6.1 client's `ClientProcess.kill` sends a signal the service reads (apple/container#1778).

## Tasks

- [x] `pluginCommand(containerVersion:)`, the `containerVersion` hook and its wiring; every CLI call uses it
- [x] Probe detects a missing plugin under either command
- [x] `pluginNames`, grouping, `clusterName(for:)`, `isK8sNode` match both labels; `isLegacy` and `isStranded`
- [x] Direct node delete for stranded clusters in delete and recreate
- [x] Stranded notice, disabled Load Image and Write Kubeconfig with help, delete confirmation copy
- [x] Copy changes and version-dependent default name
- [x] Tests in `ClusterServiceTests`: command by version (1.6.0, 1.6.1, 1.7, nil), commands issued on 1.6.1, probe on 1.6.1 missing and present, grouping with `cluster` and mixed labels, stranded delete and recreate issue `delete --force` with every node, nothing stranded on 1.6.0
- [x] README, site guide, CHANGELOG
- [x] One scoped test run of `ClusterServiceTests` and a build
- [x] A failed command's alert keeps only the last progress line and the last 10 lines of the rest (found in testing)
- [x] Package pin, `supportedContainerVersion`, hook kill, README and CHANGELOG for 1.6.1
- [x] Hand test on 1.6.0 and 1.6.1 (see the PR)
- [ ] A 1.6.1 build against a 1.6.0 install: containers, machines, a build and a hook

## Out of scope

- Reading or cleaning the plugin's state directory.

## Checked by

On 1.6.1 the Clusters tab is available, and a new cluster groups, badges, loads images, writes its kubeconfig and deletes. A cluster made on 1.6.0 still shows up after upgrading, says why its image and kubeconfig actions are off, and can be deleted or recreated. On 1.6.0 nothing changes. The unit tests cover the command choice and the stranded paths; the live 1.6.1 checks need a machine on 1.6.1.
