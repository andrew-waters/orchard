# andrew-waters/orchard#134: DNS aliases on container network attachments

https://github.com/andrew-waters/orchard/issues/134

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 20 Oct 2026

## Description

apple/container 1.6.0 adds DNS aliases to network attachments (apple/container#2390, closes apple/container#457). `--network` accepts a repeatable `alias=` property:

```
container run -d --name gateway --network default,alias=api,alias=.gateway nginx:latest
```

With default domain `test`, that container answers to `gateway.test` (its name), `api.test` (an exact alias) and every name below `gateway.test` (a **subtree alias**, written with a leading dot).

**Rules enforced by the runtime** (see `docs/architecture/dns.md` and `docs/networking.md#give-a-container-additional-dns-names` at the `1.6.0` tag):
- A name without a dot gets the default domain, just as container names do.
- Exact names are unique across all containers.
- A subtree alias must be below a name the same attachment owns, so a container can't claim another container's namespace.
- Rules are checked at create, again when a stored container starts, and again by the network helper.

Surface the runtime's validation errors as they are. Don't duplicate the rules in Orchard, apart from light client-side checks (empty or whitespace).

**Orchard work:**
- **Create/edit form** (`ContainerConfigForm.swift`, used by `RunContainer.swift` and `EditContainer.swift`): an aliases field for each network attachment (token field or add/remove list). Map it onto the attachment's alias fields in the XPC create request (`AttachmentConfiguration` in `Sources/ContainerResource/Network/`).
- **Container detail and Networks/DNS views:** list each container's aliases next to its hostname, and mark subtree aliases (for example `*.gateway.test`).
- **Cmd+K:** make aliases searchable, so typing `api.test` finds the container.
- Only show these on container 1.6.0 or later.
- Update the networks section of README.md, the site, and CHANGELOG.

**Follow-ups to file separately:**
- **Compose:** the compose package (compose.andon.dev) could now honour `networks.<net>.aliases`, and perhaps relax the README limitation that a service answers only to `<project>-<service>`. Exact aliases are still unique machine-wide, so plain service names can still collide between projects. That work belongs in the compose repo, then an Orchard bump.
- **Clusters:** upstream's motivating case is a gateway container answering for `*.gateway.test` in front of a k8s ingress. It might later become a one-click action in the cluster view.

**Depends on:** #132 (dependency bump to container 1.6.0).

**Checked by:** creating a container with `api` and `.gateway` aliases makes `api.test` and `x.gateway.test` resolve from another container; a duplicate alias on a second container shows the runtime's error in the sheet; the aliases show in container detail and the Networks view.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/134-dns-aliases-on-container-network/`: give each repo it touches a worktree there, on the branch `134-dns-aliases-on-container-network`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/134-dns-aliases-on-container-network/<name>" -b 134-dns-aliases-on-container-network origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/134-dns-aliases-on-container-network/orchard" -b 134-dns-aliases-on-container-network origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/134-dns-aliases-on-container-network/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#134" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#134]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/134-dns-aliases-on-container-network/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
