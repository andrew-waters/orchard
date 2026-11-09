# andrew-waters/orchard#174: Apple container 1.7.1: improvements

https://github.com/andrew-waters/orchard/issues/174

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 9 Nov 2026

## Description

Apple container 1.7.1 makes several things possible, or changes them, beyond what Orchard has to do to keep working (that work is in #173). These improvements bring Orchard in line with 1.7.1. Each one is gated so that older supported versions behave as they do today.

## 1. Size worker nodes separately

apple/container#2448 lets `--workers` take `count=<n>,cpus=<n>,memory=<size>` and be repeated, giving groups of workers with their own sizes. `--cpus` and `--memory` now size only the control plane once there are workers. Workers without a size get the single-node defaults (a quarter of the host's CPUs and memory, at least 2 CPUs and 2g), not the control plane's size.

Orchard's CHANGELOG says "each worker gets the same CPUs and memory as the control plane", which is no longer true on 1.7.1.

**Acceptance criteria**
- [ ] On 1.7.1 or later, Create Cluster lets the user set CPUs and memory for the workers, separately from the control plane. One worker group is enough to start with.
- [ ] The arguments are `--workers count=<n>,cpus=<n>,memory=<size>`. A plain count is still sent as `--workers <n>`, and below 1.7 only the plain form is ever sent.
- [ ] The UI says which fields size the control plane and which size the workers, and what an unsized worker gets.
- [ ] Recreate restores the worker sizes, reading them from the live worker containers when it can, and from the remembered options otherwise.
- [ ] Unit tests cover the argument building and the recreate settings.
- [ ] CHANGELOG, README and `site/clusters.html` describe worker sizing, and no longer say that workers match the control plane on 1.7.1.

## 2. Read cluster details from the new clusters service

apple/container#2451 adds a `container-core-clusters` service that stores each cluster's configuration when it is created. `container cluster ls` now prints one row per cluster (`--nodes` gives the old per-node view), and `--format json` returns the stored configuration: CNI, Kubernetes version, fqdn, nodes and roles, and creation date. Only clusters made on 1.7 or later have a stored configuration. The CLI doesn't list clusters made earlier, but delete and write-config still find them by their containers.

Orchard groups clusters from the container snapshot by name, and remembers the CNI and node image locally, because these couldn't be read back.

**Acceptance criteria**
- [ ] On 1.7.1 or later, Orchard reads `container cluster ls --format json` and merges its stored configuration with the clusters it builds from the container snapshot. Node state still comes from the snapshot.
- [ ] The Clusters list and detail show each cluster's Kubernetes version and creation date when they're known.
- [ ] Recreate takes the CNI and Kubernetes version from the stored configuration when there is one, so a cluster created outside Orchard recreates with its real settings. It falls back to the remembered options.
- [ ] Clusters with no stored configuration (made before 1.7) still show and can be deleted, with a short note that the CLI doesn't list them.
- [ ] A failed or unparseable `cluster ls` leaves the Clusters tab working from the snapshot, as today.
- [ ] Unit tests cover parsing the JSON and merging it with the snapshot grouping.

## 3. Report the recommended kernel accurately

1.7.1 recommends Kata 4.3.1 (`vmlinux-6.18.56-208-debug`). `SystemService` (around line 303) treats any `vmlinux-*` symlink target as "recommended", so someone still on the kernel 1.6.1 installed is told they're on the recommended one.

**Acceptance criteria**
- [ ] Orchard compares the installed kernel with the recommended kernel for the running container version. This comes from the system configuration or properties, not from a hard-coded name.
- [ ] When they differ, Settings shows the installed version and the recommended one, and offers **Use recommended kernel**, which runs the existing recommended-kernel path.
- [ ] A custom kernel is still shown as custom, and is not flagged as out of date.
- [ ] Unit tests cover recommended, outdated and custom kernels.

## 4. Help existing installs leave rebuildable data out of Time Machine

apple/container#2412 excludes `snapshots/` and `containers/` under the app root from backups, but only when those directories are first created. Existing installs keep backing up large sparse files that can be rebuilt, which slows backups and can cause older backups to be thinned. Named volume data under `volumes/` stays included on purpose.

**Acceptance criteria**
- [ ] Settings (or the disk usage view) shows whether `snapshots/` and `containers/` are excluded from Time Machine.
- [ ] If they aren't, a single action excludes both, using the same sticky exclusion upstream uses (what `tmutil addexclusion` sets). `volumes/` is never touched.
- [ ] The state updates after the action, and Orchard says why the exclusion is safe: the data can be rebuilt by pulling the image or recreating the container.
- [ ] Nothing changes without the user choosing it, and a user who has added the directories back to their backups is not nagged.

## 5. Retest builds on 1.7.1

apple/container#2428 and #2414 fix `container build` failures with newer BuildKit, and missing build context for steps that need the full context. Orchard needs no code change for this.

**Acceptance criteria**
- [ ] After moving to 1.7.1, builds from the Images tab are retested, including a multi-stage build and one that copies the whole context.
- [ ] Any open Orchard issues about build failures are retested on 1.7.1, and closed or updated.

## Not needed

- `container stats` now reports `cpuUtilization` in its JSON, YAML and TOML output (apple/container#2146). That is CLI output only. Orchard reads stats over XPC and already works out CPU use from `cpuUsageUsec` deltas over the measured interval (`StatsHistory.swift`), which is what upstream now does.
- The smaller install package (apple/container#2458) and moving the examples to apple/container-examples don't affect Orchard.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/174-apple-container-1-7-1-improvements/`: give each repo it touches a worktree there, on the branch `174-apple-container-1-7-1-improvements`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/174-apple-container-1-7-1-improvements/<name>" -b 174-apple-container-1-7-1-improvements origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/174-apple-container-1-7-1-improvements/orchard" -b 174-apple-container-1-7-1-improvements origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/174-apple-container-1-7-1-improvements/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#174" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/174-apple-container-1-7-1-improvements/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#174]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/174-apple-container-1-7-1-improvements/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
