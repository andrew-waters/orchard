# andrew-waters/orchard#111: Using Orchard with AppRoot on external Volume

https://github.com/andrew-waters/orchard/issues/111

- State: open
- Labels: bug
- Opened by: @andbez, 20 Sep 2026

## Description

Hi,

just wanted to test Orchard. My setup involves an AppRoot on an external Storage. Unfortunately Orchard seems to "crash" the api/setup, when started. Any idea?

Thank you.

## Comments

### @andrew-waters, 21 Sep 2026 at 9:29

Thanks for the report. I've reproduced something that looks like this locally, and I think the cause is upstream rather than in Orchard, so a couple of questions to confirm we're looking at the same thing.

**What I see here.** With an app root on a mounted volume, `container system start --app-root /Volumes/<vol>/container` fails:

```
Error: internalError: "failed to get a response from apiserver: interrupted:
  "XPC connection error: Connection invalid""
```

The chain looks like this:

1. `container system start` writes its launchd plist to `<appRoot>/apiserver/apiserver.plist` and bootstraps launchd from that path.
2. `launchctl bootstrap` refuses any plist living on the volume: `Bootstrap failed: 5: Input/output error`.
3. The apiserver never registers, so the start fails as above.

**The daemon itself is fine with data on an external volume.** Loading the identical plist, with the same `CONTAINER_APP_ROOT`, from a path on the internal disk instead:

```
paths.appRoot       /Volumes/<vol>/container/
status              running
```

So it appears to be the plist's location that launchd objects to, not the app root value. I haven't established *why* launchd refuses it, and I tested against an APFS disk image rather than real external storage, so that's worth confirming against your setup.

**Could you share:**

1. `container system status` (it reports `paths.appRoot`, which tells us where it actually ended up)
2. Whether `container system start --app-root /Volumes/...` succeeds for you **with Orchard closed**. If it fails the same way, this is apple/container and I'll raise it upstream.
3. How the app root is set: `CONTAINER_APP_ROOT` in your shell, `--app-root` by hand, or a symlink from `~/Library/Application Support/com.apple.container`?
4. Your Orchard and `container` versions.

**If you need it working now**, the workaround here was to keep the data on the volume but the plist on the internal disk: copy the generated `apiserver.plist` somewhere local and `launchctl bootstrap gui/$UID <local-path>`. The `CONTAINER_APP_ROOT` inside the plist keeps pointing at the volume.

Separately, there's a real gap on Orchard's side: it runs `container system start` with no `--app-root`, and a Finder-launched app doesn't inherit your shell's `CONTAINER_APP_ROOT`, so it would start the daemon against the default location regardless of your configuration. I'll fix that. It wouldn't have helped here, though, since the bootstrap fails whoever runs it.


### @andbez, 21 Sep 2026 at 16:46

Hi Andrew,

Thanks for your information. I am on a business trip and will answer your questions until Wednesday. But what I can say: my setup worked with several containers before trying to use orchard. I am starting container system start -- approot .... manually on the cli.

Best
Andreas

### @andbez, 23 Sep 2026 at 15:56

Hi Andrew,

as written here are the answers to the inquired questions:

1. ➜  ContainerData git:(main) ✗ container system status
FIELD               VALUE
status              running
client.version      1.4.1
client.build        release
client.commit       9a8917ca2da5cd6ba059b9ba5ca5a74892e9bb7d
host.os             Version 26.7 (Build 25G229)
host.architecture   arm64
host.cpus           24
server.version      1.4.1
server.build        release
server.commit       9a8917ca2da5cd6ba059b9ba5ca5a74892e9bb7d
server.appName      container-apiserver
paths.appRoot       /Volumes/Mate_SSD1/ContainerRoot/AppRoot/
paths.installRoot   /usr/local/
paths.logRoot       
containers.total    12
containers.running  11
images.total        13
2. Yes, as you can see with the status
3. By hand: container system start --app-root /Volumes/Mate_SSD1/ContainerRoot/AppRoot/
4.
>  container --version
container CLI version 1.4.1 (build: release, commit: 9a8917c)

> brew info orchard                  
==> orchard ✔ (Orchard): 2.4.2
Native GUI for Apple Containers
https://github.com/andrew-waters/orchard
Installed (on request)
/opt/homebrew/Caskroom/orchard/2.4.2 (65.3MB)
  Installed using the internal formulae.brew.sh API on 2026-09-20 at 08:59:21
From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/o/orchard.rb

I had the same issue with the api-server, because I am running container on a headless Mac Studio. You have to login with the user you try to run container and give permission to several commands in privacy and security settings. Also the external Volume has to be set with ownership enabled. After all this is given, the api starts with the plist on the external volume.

I hope this helps.

Thank you 
Andreas

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/111-using-orchard-with-approot-on-external/`: give each repo it touches a worktree there, on the branch `111-using-orchard-with-approot-on-external`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/111-using-orchard-with-approot-on-external/<name>" -b 111-using-orchard-with-approot-on-external origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. You're in a sandbox: only the repos already under `projects/` are here (andrew-waters/orchard), and a clone made in it would vanish when it stops. If the issue needs another repo, stop and ask the user to clone it into `projects/` on their Mac and restart the session. Commits are signed for you. The repos' git dirs are read-only apart from what commits, fetches and worktrees write, so git config and hooks can't be changed, no upstream is recorded (push with `git push origin HEAD:111-using-orchard-with-approot-on-external` and open the PR with `gh pr create --head <branch>`), branches can't be deleted, and an error about packed-refs.lock after a rebase or pull is expected and harmless.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/111-using-orchard-with-approot-on-external/orchard" -b 111-using-orchard-with-approot-on-external origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/111-using-orchard-with-approot-on-external/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#111" in its body so it links to the issue.
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#111]` and a summary in its front matter as the harness's STANDARDS.md sets out, so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/111-using-orchard-with-approot-on-external/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
