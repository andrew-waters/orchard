# andrew-waters/orchard#173: Support Apple container 1.7.1: must-change

https://github.com/andrew-waters/orchard/issues/173

- State: open
- Labels: bug
- Opened by: @andrew-waters, 9 Nov 2026

## Description

Apple container 1.7.1 (apple/container 1.7.1; 1.7.0 was tagged but never released) changes behaviour that Orchard depends on. Orchard links the 1.6.1 client and talks to the services over XPC, so it also skips some guards that are new in the 1.7.1 CLI. These are the changes Orchard needs before it can support 1.7.1.

The general move away from a single pinned version is in #172. This issue covers what 1.7.1 itself breaks or changes.

## 1. Support container 1.7.1

Orchard pins the `container` package at 1.6.1 (containerization 0.53.0) and sets `supportedContainerVersion = "1.6.1"` (`Orchard/Services/ContainerBackend.swift:242`). 1.7.1 brings containerization 0.54.0. The installer asset keeps the same name pattern (`container-1.7.1-installer-signed.pkg`).

**Acceptance criteria**
- [ ] The `container` package resolves to 1.7.1 and containerization to 0.54.0, and Orchard builds against them.
- [ ] `supportedContainerVersion` (or the version range from #172) recommends 1.7.1, and **Install container** downloads and installs `container-1.7.1-installer-signed.pkg`.
- [ ] With a 1.7.1 daemon running, Orchard reports the system as running, not "version not yet supported" or "unsupported version", and the containers, images, machines, volumes, networks and clusters tabs all load.
- [ ] Every existing version gate (`supportsWorkerNodes`, `supportsNoCNI`, `pluginCommand` and so on) still gives the right answer on 1.7.1 and on the oldest supported version.

## 2. Load Image is removed from the cluster plugin

apple/container#2437 removed `container cluster load-image`. Its replacement is `container cluster create --shared-image-store`, which lets the nodes pull from the Mac's own `container` image store. (The release notes say `cluster run`, but the flag is on `ClusterCreate`.) A cluster only gets this when it is created, so an existing cluster gains it only by being recreated.

Today `ClusterService.loadImage` (`ClusterService.swift:657`) and the Load Image sheet in `ClusterDetail.swift` (around lines 166 and 436 to 500) run `load-image`, which fails on 1.7.1.

**Acceptance criteria**
- [ ] On 1.7.1 or later, Orchard never runs `cluster load-image`, and no Load Image action is offered.
- [ ] Below 1.7, Load Image works as it does today.
- [ ] On 1.7.1 or later, Create Cluster offers a **Use local images** option that passes `--shared-image-store`. The option is on by default.
- [ ] The option is remembered with the cluster's other create options, and Recreate restores it.
- [ ] A cluster's detail says whether it can see local images. A cluster without the option points the user to Recreate to turn it on.
- [ ] A test covers the create arguments with and without the option, and on a version that doesn't support it, where the flag is never passed.
- [ ] CHANGELOG, README and `site/clusters.html` describe the new behaviour and no longer offer Load Image on 1.7.1.

## 3. Cluster nodes can't be started, stopped, killed, deleted or pruned on their own

apple/container#2462 makes the CLI hide cluster nodes from `ls`, `start`, `stop`, `kill`, `delete` and `prune`. A node acted on by itself breaks the cluster's kubeadm state. `logs` still works on nodes. Orchard uses the XPC client directly, so it skips this filter.

Orchard already blocks Start on a node (`ContainerListService.swift:170`). But these still act on nodes:
- Stop, Kill and Delete in the container detail header and context menu
- **Stop All** (`ListContainers.swift:185`)
- the multi-select cards (`MultiContainerCards.swift`)
- the menu bar dashboard
- the command palette's stop action

**Acceptance criteria**
- [ ] Stop, Kill, Restart and Delete are hidden or disabled for a cluster node wherever Orchard offers them: the detail header, context menu, multi-select cards, menu bar, command palette and deep links. Where disabled, the help text points to the cluster.
- [ ] Bulk actions (Start All, Stop All, multi-select stop and delete) leave cluster nodes out, and their counts exclude them.
- [ ] `ContainerListService` refuses stop, kill and delete for a cluster node as a backstop, the same way it refuses start today, and says why.
- [ ] Logs, Exec/terminal, Stats and Export still work on a node.
- [ ] A cluster made before the `k8s` to `cluster` rename (labelled `k8s`) can still be deleted from Clusters. Upstream filters only the `cluster` label, so Orchard's direct node delete still applies there.
- [ ] Free Up Space keeps excluding cluster nodes. It already excludes plugin-owned containers.
- [ ] Unit tests cover the node filtering for the bulk actions and the service backstop.

## 4. DNS defaults from config.toml are ignored for containers Orchard creates

apple/container#1614 adds default `nameservers`, `searchDomains`, `options` and `domain` under `[container.dns]` in `~/.config/container/config.toml`. The CLI applies them on the client side in `Utility.dnsConfiguration(from:defaults:hostDomainFallback:)`, so the API server never sees them. The order of precedence is explicit flags, then the `[container.dns]` defaults, then the host's `[dns].domain`.

Orchard builds its own `DNSConfiguration` in `ContainerBackend.createContainer` (around line 620), so a container created in Orchard ignores those defaults, while one made with `container run` honours them.

**Acceptance criteria**
- [ ] A container created in Orchard (the create form, compose, sandboxes and model servers) resolves DNS with the same precedence as `container run`: each field set in Orchard wins, then `[container.dns]`, then `[dns].domain`.
- [ ] Orchard still always sends a resolver configuration (the existing rule that keeps `/etc/resolv.conf` from going missing), and still adds the default nameservers when only a domain is set.
- [ ] Settings shows the configured `[container.dns]` defaults read-only, next to the existing DNS domain row (`SettingsView.swift`, around lines 141 and 187), and explains that they live in `config.toml`.
- [ ] The DNS fields in the container form show the defaults as placeholders, so leaving a field empty visibly means "use the default".
- [ ] Unit tests cover the precedence: no defaults, defaults only, an Orchard field overriding a default, and the domain fallback.

The follow-on improvements that 1.7.1 makes possible are in #174.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/173-support-apple-container-1-7-1-must/`: give each repo it touches a worktree there, on the branch `173-support-apple-container-1-7-1-must`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/173-support-apple-container-1-7-1-must/<name>" -b 173-support-apple-container-1-7-1-must origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/173-support-apple-container-1-7-1-must/orchard" -b 173-support-apple-container-1-7-1-must origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/173-support-apple-container-1-7-1-must/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#173" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/173-support-apple-container-1-7-1-must/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#173]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/173-support-apple-container-1-7-1-must/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
