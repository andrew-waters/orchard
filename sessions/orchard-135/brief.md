# andrew-waters/orchard#135: Create clusters with no CNI

https://github.com/andrew-waters/orchard/issues/135

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 20 Oct 2026

## Description

apple/container 1.6.0 lets `container k8s create --cni NONE` (case-insensitive) skip CNI installation (apple/container#2277). The command then returns **without waiting for nodes to become Ready**, because that needs a CNI. The user applies their own with `kubectl apply` afterwards. This suits people who install Cilium or Calico with Helm or their own steps, which a single manifest file can't express.

**Orchard work:**
- In `CreateCluster.swift` (`cniField`, around line 190), make the CNI choice three-way: "Default (kindnet)", "Custom manifest" (the existing file picker) and "None (install your own)". Pass `--cni NONE` for the last (`ClusterService.swift`, where `--cni` is appended around line 330).
- Remember the choice for recreate. `cni` is currently `String?` for a path; store "none" distinctly so it is not treated as a path.
- **Cluster status:** a cluster created with no CNI has NotReady nodes until the user installs one. Check how the cluster list and detail present that state. It should read as "waiting for a CNI" with a short hint (and the docs link already in the sheet), not as failed or broken.
- Only offer "None" on container 1.6.0 or later (`SystemService.containerVersion`).
- Update the Clusters section of README.md, the site's clusters guide, and CHANGELOG.

**Depends on:** #132 (dependency bump to container 1.6.0). Small, and pairs naturally with #87 (worker nodes) if the same person picks both up.

**Checked by:** creating a cluster with "None" finishes promptly; the cluster shows the waiting-for-CNI state; applying a CNI with `kubectl` brings the nodes to Ready and the state clears; recreating keeps "None".

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/135-create-clusters-with-no-cni/`: give each repo it touches a worktree there, on the branch `135-create-clusters-with-no-cni`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/135-create-clusters-with-no-cni/<name>" -b 135-create-clusters-with-no-cni origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/135-create-clusters-with-no-cni/orchard" -b 135-create-clusters-with-no-cni origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/135-create-clusters-with-no-cni/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#135" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#135]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/135-create-clusters-with-no-cni/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
