# andrew-waters/orchard#170: Bump SwiftNIO packages to clear Dependabot security alerts

https://github.com/andrew-waters/orchard/issues/170

- State: open
- Opened by: @andrew-waters, 6 Nov 2026

## Description

Dependabot has five open alerts, all in Apple's SwiftNIO packages pinned in `Orchard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

| Alert | Severity | Package (pinned) | Fixed in | Summary |
|---|---|---|---|---|
| #3 | High | swift-nio (2.97.1) | 2.100.0 | NIOHTTP1 `HTTPDecoder` accepts unbounded HTTP/1 header blocks, enabling remote DoS |
| #2 | High | swift-nio (2.97.1) | 2.100.0 | Out-of-bounds write via `ByteBuffer` index and length UInt32 overflow |
| #1 | Medium | swift-nio (2.97.1) | 2.100.0 | CRLF injection in outbound HTTP request URI via `NIOHTTPRequestHeadersValidator` |
| #4 | Medium | swift-nio-extras (1.33.0) | 1.34.1 | `NIOHTTPRequestDecompressor` ratio limit bypass via inflated Content-Length |
| #5 | Medium | swift-nio-http2 (1.42.0) | 1.44.0 | HTTP/2-to-HTTP/1 request smuggling via unvalidated `:path` pseudo-header in `HTTP2ToHTTP1Codec` |

Alerts: https://github.com/andrew-waters/orchard/security/dependabot

## Fix

Bump the three packages to at least:

- swift-nio 2.100.0
- swift-nio-extras 1.34.1
- swift-nio-http2 1.44.0

These appear to be transitive dependencies, so updating packages in Xcode (or editing `Package.resolved`) should be enough, provided the packages that depend on them allow those versions.

## Done when

- [ ] `Package.resolved` pins the patched versions
- [ ] The app builds and runs
- [ ] All five Dependabot alerts close

## Working here

- You're in the team's harness, andrew-waters/orchard, checked out at `~/Code/andrew-waters/orchard`. Its CLAUDE.md lists the projects and how work goes here.
- The code repos are shared clones under `projects/<name>` (some a folder further down, as `projects/<group>/<name>`), kept on their default branch. Don't work in them. This issue's folder is `.worktrees/170-bump-swiftnio-packages-to-clear/`: give each repo it touches a worktree there, on the branch `170-bump-swiftnio-packages-to-clear`, from the harness root:

  ```bash
  git -C projects/<name> fetch origin
  git -C projects/<name> worktree add "$PWD/.worktrees/170-bump-swiftnio-packages-to-clear/<name>" -b 170-bump-swiftnio-packages-to-clear origin/HEAD
  ```

  If the branch already exists, leave out `-b` and `origin/HEAD`. If a repo isn't under `projects/` yet, clone it there first with `gh repo clone <owner>/<name> projects/<name>`.
- If the harness has no `projects/` folder, it's the code repo too: the code is andrew-waters/orchard itself. Don't work in its checkout; give it one worktree in the issue's folder the same way, with `git -C . fetch origin` and `git -C . worktree add "$PWD/.worktrees/170-bump-swiftnio-packages-to-clear/orchard" -b 170-bump-swiftnio-packages-to-clear origin/HEAD`, and do everything there, the plan included.
- When the change is ready for review (committed, built and checked; before a pull request is opened as ready for review, though a draft is fine), run `.worktrees/170-bump-swiftnio-packages-to-clear/.gannin/ready-for-review "<what changed and where to look>"` and end your turn. Gannin may have a second agent review it; it can't edit, and its findings come back to you as a message. Fix those you agree with, say why not for the rest, commit, and run the script again. Gannin says when the review has settled, or to carry on without one.
- Commit in each worktree, and open a pull request per repo with `gh pr create`, putting "Closes andrew-waters/orchard#170" in its body so it links to the issue. Before opening it as ready for review, run `.worktrees/170-bump-swiftnio-packages-to-clear/.gannin/ready-for-review "<what changed and where to look>"` and wait for its outcome (opening it as a draft first is fine).
- A plan for this issue goes in the harness as `plans/YYYY-MM-DD-<slug>.md` from `plans/_template.md` (older harnesses keep plans in `requirements/<module>/plans/`), with `issues: [andrew-waters/orchard#170]` and a summary in its front matter as `~/Code/andrew-waters/orchard/STANDARDS.md` sets out, if the harness has one (don't look for it anywhere else), so Gannin links it to the issue. Commit and push it in the harness, and tick its checkboxes off as tasks land. When the harness is the code repo, the plan goes in its worktree and ships in the same pull request, and only if the repo keeps a `plans/` folder.
- `.worktrees/170-bump-swiftnio-packages-to-clear/.gannin/` is Gannin's (this brief and the session's hooks). `.worktrees/` and `projects/` are kept out of the harness's git.
