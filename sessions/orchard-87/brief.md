# andrew-waters/orchard#87: Create clusters with worker nodes

https://github.com/andrew-waters/orchard/issues/87

- State: open
- Opened by: @andrew-waters, 20 Aug 2026

## Description

apple/container 1.6.0 shipped multi-node clusters (apple/container#2276), but not in the shape this issue originally anticipated: worker nodes can only be requested when a cluster is created. There is still no command to add a node to a running cluster.

**Upstream surface (1.6.0):**
- `container k8s create --workers <n>`: number of worker nodes (default `0`, meaning the control plane also runs workloads). Workers are named `<cluster>-worker-N`.
- `container k8s delete` now removes the worker nodes as well as the control plane.
- `container k8s load-image --node <name>` (repeatable) loads an image into the named nodes only; without it, every node gets the image.
- apple/container#2315 fixed list grouping for control-plane nodes that also carry the worker role.

See `docs/command-reference.md` at the `1.6.0` tag, section "Kubernetes Cluster Management".

**Orchard work:**
- Add a "Workers" stepper (0 upwards, default 0) to `CreateCluster.swift`, in the advanced section beside the CNI field. Pass `--workers` from `ClusterService.create` / `recreate` (`ClusterService.swift` around line 324, where `--cni` is appended), and remember it with the other recreate options.
- In the load-image flow, add a node picker (all nodes by default). Pass one `--node` per selected node when the selection is not "all".
- Remove or version-gate the "can't add worker nodes yet" caption in `ClusterDetail.swift:188`.
- Check `K8sCluster.group` (`ClusterService.swift`) against upstream's grouping fix (#2315): a control-plane node whose roles include `worker` must still be treated as the control plane and must not show up as an orphan.
- Only offer the stepper and node picker when the installed container is 1.6.0 or later (`SystemService.containerVersion`).
- Update the Clusters section of README.md and `site/` (clusters guide), and add a CHANGELOG entry.

**Out of scope until upstream supports it:** adding a node to an existing cluster. We do not reimplement node join (kubeadm tokens, prep scripts) in Orchard, for the same reasons as #71 and #51.

**Depends on:** #132 (dependency bump to container 1.6.0).

**Checked by:** creating a cluster with 2 workers shows three nodes in the nodes table with correct roles; deleting it removes all three containers; loading an image into one worker makes it available there only (`crictl images` on each node); a pre-1.6.0 install shows neither control.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/87-create-clusters-with-worker-nodes/`: give each repo it touches a worktree there, on the branch `87-create-clusters-with-worker-nodes`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/87-create-clusters-with-worker-nodes/<name>" -b 87-create-clusters-with-worker-nodes origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/87-create-clusters-with-worker-nodes/orchard" -b 87-create-clusters-with-worker-nodes origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/87-create-clusters-with-worker-nodes/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#87" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#87]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/87-create-clusters-with-worker-nodes/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
