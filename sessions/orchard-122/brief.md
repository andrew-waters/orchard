# andrew-waters/orchard#122: A sandbox is an isolated workload, with or without a model

https://github.com/andrew-waters/orchard/issues/122

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 9 Oct 2026

## Description

## Problem

Orchard treats a sandbox as "a workload wired to a local model" (`Orchard/Services/Sandbox.swift`, `SandboxMarker`): a container is one only when it has `com.orchard.sandbox=true` with a model endpoint, or `OPENAI_BASE_URL`, `OLLAMA_HOST` or `ANTHROPIC_BASE_URL` in its environment.

What makes a container a sandbox is what it can't reach: the files, keys and network it's kept from. A model endpoint is one thing a sandbox may have, not what makes it one. Gannin is about to run its Claude Code sessions in Apple container sandboxes (andrew-waters/gannin#8): a read-only harness, other sessions' folders and other repos' working trees hidden, resource caps, and no model endpoint at all in its first version. Those containers show in Orchard as ordinary containers, not in the Sandbox tab.

## Proposal

A label contract both apps follow, on the container:

| Label | Meaning |
|---|---|
| `com.orchard.sandbox=true` | A sandbox: an isolated workload. The label alone is enough. |
| `com.orchard.sandbox.owner` | The app that made it and manages its lifecycle, such as `dev.andon.gannin`. Absent means Orchard's own. |
| `com.orchard.sandbox.network` | `nat`, `host-only` or `allowlist`. |
| `com.orchard.model.endpoint` | Optional, as today. |

Changes in Orchard:

- `SandboxMarker`: the sandbox label alone makes a sandbox. The model endpoint becomes optional; the model tester shows only when there is one. The environment heuristic stays for detecting sandboxes made elsewhere.
- The Sandbox tab and a sandbox's detail show how it's contained, not only its model: network mode, mounts (read-only or read-write, and tmpfs masks), CPU and memory, and the owner.
- A sandbox owned by another app (`com.orchard.sandbox.owner` not Orchard) gets a badge naming it ("Gannin session"), and Stop and Delete warn that the other app manages it, so Orchard doesn't pull a container out from under a running session.
- Orchard keeps stamping `com.orchard.sandbox.owner` absent (or its own bundle ID) on the sandboxes it makes, and `network` from its host-only setting.

Gannin's side (andrew-waters/gannin#8, task andrew-waters/gannin#82) stamps `com.orchard.sandbox=true`, `com.orchard.sandbox.owner=dev.andon.gannin` and `com.orchard.sandbox.network=nat`, keeping `dev.andon.gannin=1` for its own cleanup. Gannin doesn't depend on Orchard; the labels are just what Orchard reads.

## Acceptance

- [ ] A container labelled `com.orchard.sandbox=true` with no model endpoint and no model environment variables is listed in the Sandbox tab.
- [ ] Sandboxes with a model endpoint behave as today, tester included; those without one don't offer the tester.
- [ ] A sandbox's network mode, mounts, CPU and memory and owner are shown.
- [ ] A sandbox owned by another app is badged with it, and Stop and Delete warn before acting.
- [ ] `SandboxMarker` tests cover the label alone, label with endpoint, environment only, and owner.

## Context

- Gannin's plan: andrew-waters/gannin `plans/2026-10-09-run-agent-sessions-in-apple-container.md`, whose spike ran a labelled container with masked same-path mounts on container 1.4.1 and 1.5.0.
- Network in Gannin's first version is open NAT; an egress allow list is a follow-up, which `com.orchard.sandbox.network=allowlist` is there for.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/122-a-sandbox-is-an-isolated-workload-with/`: give each repo it touches a worktree there, on the branch `122-a-sandbox-is-an-isolated-workload-with`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/122-a-sandbox-is-an-isolated-workload-with/<name>" -b 122-a-sandbox-is-an-isolated-workload-with origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/122-a-sandbox-is-an-isolated-workload-with/orchard" -b 122-a-sandbox-is-an-isolated-workload-with origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/122-a-sandbox-is-an-isolated-workload-with/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#122" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/122-a-sandbox-is-an-isolated-workload-with/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#122]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/122-a-sandbox-is-an-isolated-workload-with/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
