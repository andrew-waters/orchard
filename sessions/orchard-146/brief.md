# andrew-waters/orchard#146: Support container 1.6.1's rename of the k8s plugin to cluster

https://github.com/andrew-waters/orchard/issues/146

- State: open
- Labels: bug
- Opened by: @andrew-waters, 26 Oct 2026

## Description

apple/container 1.6.1 renames the experimental Kubernetes plugin from `k8s` to `cluster` (apple/container#2427). It shipped in a patch release, and it breaks Orchard's Clusters feature for anyone who upgrades.

**What breaks on 1.6.1:**
- **The subcommand is now `container cluster ...`.** `ClusterService.swift` runs `["k8s", ...]` everywhere: the plugin probe (around line 347), the `create --help` read for the default node image (374), create (414), delete (474, 491), `load-image` (613) and `write-config` (621). The probe gets `unknown command 'k8s'`, which line 353 reads as `.missingPlugin`. So the Clusters tab tells 1.6.1 users they need container 1.2.2 or later.
- **Node containers now get a new label value:** `com.apple.container.plugin=cluster` instead of `k8s`. `K8sCluster.pluginName = "k8s"` (`ClusterService.swift:23`) drives cluster grouping and `isK8sNode` (`PluginResource.swift:21`). Nodes of a new cluster would show as loose containers, and Start would no longer be swapped for Recreate on them.
- **Clusters created on 1.6.0 or earlier get stranded.** Upstream's list, delete and load-image now filter on the `cluster` label only, so `container cluster delete` can't see nodes labelled `k8s`.
- The plugin's state directory and default cluster name moved too (`plugins/k8s` to `plugins/cluster`, `k8s-dev` to `cluster-dev`). Nothing in Orchard reads either one today, but worth checking.

**Orchard work:**
- Choose the subcommand by `SystemService.containerVersion`: `cluster` on 1.6.1 or later, `k8s` before that. Keep this in one place so every call site uses it.
- Treat a node as a cluster node when the plugin label is either `cluster` or `k8s`, for grouping, `isK8sNode` and the list badge.
- Handle legacy (`k8s`-labelled) clusters on 1.6.1: still list them, but delete their node containers directly, since the CLI can't find them. Offer Recreate so they come back under the new label. Load image and write config won't work for these through the CLI, so either disable them with an explanation or point the user to Recreate.
- Update the probe's missing-plugin detection for both command names.
- User-facing copy that says "the k8s plugin" (`ListClusters.swift:96`, `CreateCluster.swift:196` and 246, `ClusterDetail.swift:206`): say "Apple container's cluster plugin" or similar, regardless of version.
- Update the Clusters section of README.md, the site's clusters guide, and CHANGELOG.

**Checked by:** on 1.6.1, the Clusters tab is available, and a new cluster groups, badges, loads images, writes its kubeconfig and deletes. A cluster made on 1.6.0 still shows up after upgrading and can be deleted or recreated. On 1.6.0, nothing changes.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/146-support-container-1-6-1-s-rename-of-the/`: give each repo it touches a worktree there, on the branch `146-support-container-1-6-1-s-rename-of-the`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/146-support-container-1-6-1-s-rename-of-the/<name>" -b 146-support-container-1-6-1-s-rename-of-the origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/146-support-container-1-6-1-s-rename-of-the/orchard" -b 146-support-container-1-6-1-s-rename-of-the origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/146-support-container-1-6-1-s-rename-of-the/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#146" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/146-support-container-1-6-1-s-rename-of-the/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#146]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/146-support-container-1-6-1-s-rename-of-the/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
