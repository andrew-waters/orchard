---
type: plan
status: in-progress
summary: "Re-resolve swift-nio, swift-nio-extras and swift-nio-http2 to their latest compatible releases (at least 2.100.0, 1.34.1 and 1.44.0) to clear Dependabot alerts #1 to #5. Package.resolved only; no project or code changes expected."
issues: [andrew-waters/orchard#170]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-11-06
---

# Bump SwiftNIO packages

Dependabot flags five advisories against the SwiftNIO pins in `Orchard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: swift-nio 2.97.1, swift-nio-extras 1.33.0 and swift-nio-http2 1.42.0.

## Where the pins come from

Orchard declares only three packages in `project.pbxproj`: container, compose and Sparkle. The NIO packages arrive transitively through container, containerization, grpc-swift-nio-transport and async-http-client, all of which ask for `from:` (up to next major). So the fixed releases are inside the allowed range and no requirement in `project.pbxproj` changes.

Latest tags today: swift-nio 2.105.0, swift-nio-extras 1.35.2, swift-nio-http2 1.46.0.

## Approach

Remove the three NIO pins from `Package.resolved` and let `xcodebuild -resolvePackageDependencies` resolve them again. SwiftPM keeps every other pin it can, so this takes the latest compatible NIO releases and moves other pins only if those releases require it. Any knock-on moves are listed in the pull request.

Taking the latest releases rather than the exact minimum fixed versions avoids hand-writing revisions, and picks up later fixes in the same majors.

## Out of scope

- Bumping container, containerization, compose or Sparkle.
- A general refresh of every pin.

## Tasks

- [x] Re-resolve the three NIO pins: swift-nio 2.105.0, swift-nio-extras 1.35.2, swift-nio-http2 1.46.0
- [x] Note any other pins that moved: swift-http-types 1.5.1 to 1.8.0 and swift-http-structured-headers 1.6.0 to 1.7.0, both required by the new NIO releases
- [x] App builds (Debug); OrchardTests pass (596 tests)
- [x] Launch the app and check containers list, logs and image pulls still work (the paths that use NIO via container and containerization)
- [ ] After merge, Dependabot alerts #1 to #5 close
