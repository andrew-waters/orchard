import Foundation

/// Best-effort advice about whether an image will boot as a container machine.
///
/// A machine runs the image's init system (systemd/openrc) as PID 1 at `/sbin/init`. Stock
/// base and application images don't ship one, so they boot and then immediately stop
/// (exit 127, "`exec: /sbin/init: not found`") — upstream limitation apple/container#1669.
/// We can't read the image filesystem before pulling it, so this is a name heuristic: it
/// catches the common mistakes without pretending to be authoritative.
enum MachineImageAdvisor {
    /// Well-known images whose PID 1 is not an init system.
    private static let initlessNames: Set<String> = [
        "alpine", "busybox", "scratch", "hello-world",
        "ubuntu", "debian", "fedora", "centos", "rockylinux", "almalinux", "archlinux", "opensuse",
        "nginx", "httpd", "caddy", "traefik", "haproxy",
        "redis", "postgres", "mysql", "mariadb", "mongo", "memcached",
        "node", "python", "golang", "go", "openjdk", "eclipse-temurin", "ruby", "php", "rust", "elixir",
    ]

    /// True when `imageRef` is very likely to lack an init system (so a machine would boot then
    /// stop). Images whose reference mentions `init`/`systemd` are treated as fine.
    static func likelyLacksInit(_ imageRef: String) -> Bool {
        let lower = imageRef.lowercased()
        guard !lower.isEmpty else { return false }
        if lower.contains("init") || lower.contains("systemd") { return false }

        // Reduce to the repository's last path component: drop any @digest, then :tag, then
        // registry/org prefix (e.g. "docker.io/library/ubuntu:24.04" → "ubuntu").
        let withoutDigest = lower.split(separator: "@", maxSplits: 1).first.map(String.init) ?? lower
        let withoutTag = withoutDigest.split(separator: ":", maxSplits: 1).first.map(String.init) ?? withoutDigest
        let name = withoutTag.split(separator: "/").last.map(String.init) ?? withoutTag

        return initlessNames.contains(name)
    }

    /// Authoritative (unlike `likelyLacksInit`): true when a machine's logs show it stopped
    /// because the image has no init system — the init exec failed, e.g.
    /// `exec: /sbin/init: not found` or `can't run '/sbin/openrc': No such file or directory`.
    /// Read from a stopped machine's stdio/boot logs to explain *why* it stopped.
    static func logsIndicateMissingInit(_ logLines: [String]) -> Bool {
        for line in logLines {
            let lower = line.lowercased()
            let mentionsInit = lower.contains("/sbin/init") || lower.contains("/sbin/openrc")
            let missing = lower.contains("not found") || lower.contains("no such file")
            if mentionsInit && missing { return true }
        }
        return false
    }
}
