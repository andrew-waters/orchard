# andrew-waters/orchard#116: Bug DNS when set to Default

https://github.com/andrew-waters/orchard/issues/116

- State: open
- Labels: bug
- Opened by: @adityadarma, 5 Oct 2026

## Description

## Describe the bug

Setting a default DNS domain fails because Orchard invokes an unsupported Apple Container CLI command:

```text
container system property set dns.domain <domain>
The CLI returns:
Error: 3 unexpected arguments: 'set', 'dns.domain', '<domain>'
Usage: container system property [--debug] <subcommand>
See 'container system property --help' for more information.
The default DNS domain is not set.

## To reproduce

1. Open Orchard.
2. Go to the DNS view, or open Settings > General.
3. Create or select an existing DNS domain.
4. Click Make Default, or select the domain as DNS Domain in Settings.
5. See the CLI error.

## Expected behaviour

Orchard should set the selected DNS domain as the default without calling an unsupported container system property set command.
If Apple Container no longer provides a writable dns.domain system property, Orchard should store this preference locally and use it when creating new containers.

## Screenshots / logs

Error: 3 unexpected arguments: 'set', 'dns.domain', 'backend'
Usage: container system property [--debug] <subcommand>
See 'container system property --help' for more information.
container system property --help:
OVERVIEW: Manage system property values

USAGE: container system property [--debug] <subcommand>

SUBCOMMANDS:
  list, ls                List system properties
container system property set returns:
Error: unknown command 'system property set'
Usage: container [--debug] <subcommand>
See 'container --help' for more information.

## Environment

- Orchard version: <!-- 2.5.0 -->
- macOS version: <!-- 26.7.1 (Tahoe) -->
- `container` version: <!-- 1.5.0 -->
- Apple silicon or Intel: <!-- M2 -->

## Additional context

The same upstream CLI structure exists in Apple Container 1.4.1: container system property only registers the list / ls subcommand and does not implement set.
Relevant upstream files:
- https://raw.githubusercontent.com/apple/container/1.4.1/Sources/ContainerCommands/System/SystemProperty.swift
- https://raw.githubusercontent.com/apple/container/1.4.1/Sources/ContainerCommands/System/Property/PropertyList.swift
Suggested resolution: keep Orchard's default DNS selection as an application preference instead of attempting to write dns.domain through container system property set.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/116-bug-dns-when-set-to-default/`: give each repo it touches a worktree there, on the branch `116-bug-dns-when-set-to-default`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/116-bug-dns-when-set-to-default/<name>" -b 116-bug-dns-when-set-to-default origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/116-bug-dns-when-set-to-default/orchard" -b 116-bug-dns-when-set-to-default origin/HEAD`, and do everything there, the plan included.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#116" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#116]` and a summary in its front matter as the harness's STANDARDS.md sets out, so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/116-bug-dns-when-set-to-default/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
