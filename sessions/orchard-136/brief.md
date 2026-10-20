# andrew-waters/orchard#136: Set the user account when creating a machine

https://github.com/andrew-waters/orchard/issues/136

- State: open
- Labels: enhancement
- Opened by: @andrew-waters, 20 Oct 2026

## Description

apple/container 1.6.0 reworked how a machine's user account is set up (apple/container#2322). Image-provided setup scripts are gone, and `container machine create` gains explicit **User Options**:

- `-u, --user <user>`: account user (`name|uid[:gid]`), defaults to the host user
- `--uid <uid>`: defaults to the host user's
- `--gid <gid>`: defaults to the host user's
- `--home <home>`: home directory inside the machine, defaults to `/home/<user>`

The upstream docs (`docs/container-machine.md` at `1.6.0`) also now state the convenience/isolation tradeoffs of the home mount more clearly. Read them before writing any UI copy.

**Orchard work:**
- `CreateMachine.swift`: add an "Account" group to the advanced options with user, UID, GID and home directory. Leave them empty by default, with placeholders showing the host user's values. Only send what the user changed.
- Map the fields onto the new user-setup configuration in `MachineBackend.swift` (machines are created over XPC with `MachineAPIClient`, not the CLI). The types are `MachineConfiguration` / `MachineUserSetup` under `Sources/Services/MachineAPIService/Client/`.
- Show the account in `DetailMachine.swift` next to "Home Mount".
- If `EditMachine.swift` can apply these after creation (check whether the runtime allows it), add them there too; otherwise make them create-only.
- Revisit `homeMountCaption` in `CreateMachine.swift` against upstream's updated tradeoff wording.
- Only show the fields on container 1.6.0 or later.
- Update the Container Machines section of README.md, the site's machines guide, and CHANGELOG.

**Depends on:** #132 (dependency bump to container 1.6.0). That issue may already have to touch these types to get the app compiling, so pick it up after that lands.

**Checked by:** creating a machine with a custom user, UID and home lets `id` and `echo $HOME` inside the machine report those values; creating with defaults still matches the host user; the detail view shows the account.

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/136-set-the-user-account-when-creating-a/`: give each repo it touches a worktree there, on the branch `136-set-the-user-account-when-creating-a`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/136-set-the-user-account-when-creating-a/<name>" -b 136-set-the-user-account-when-creating-a origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/136-set-the-user-account-when-creating-a/orchard" -b 136-set-the-user-account-when-creating-a origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/136-set-the-user-account-when-creating-a/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#136" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#136]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/136-set-the-user-account-when-creating-a/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
