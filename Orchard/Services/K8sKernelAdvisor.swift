import Foundation

/// Best-effort advice about whether the guest kernel can bootstrap a Kubernetes cluster.
///
/// `container k8s create` prepares its node with `iptables-nft`, which needs a guest kernel
/// built with nftables (`CONFIG_NF_TABLES`). Kernels from before container 1.3.0 are not, so
/// node preparation aborts. The abort is badly disguised: the two `iptables-nft` calls are the
/// last lines of a `set -e` script, so what the CLI reports is the accumulated output of the
/// steps that already succeeded (`net.ipv4.ip_forward = 1`, a sysctl that worked) rather than
/// the command that failed - upstream limitation apple/container#2120, still open, with no fix
/// in 1.4.1.
///
/// The reason a current install hits this at all is apple/container#905: `container system
/// start` skips the kernel download whenever a kernel already exists, so upgrading the CLI
/// never replaces the old one. Any install carried forward from before 1.3.0 keeps a kernel
/// without nftables and fails every `k8s create`, however new the CLI is.
enum K8sKernelAdvisor {
    /// The host's own architecture first, then the other. Only one pointer normally exists, so
    /// the order rarely matters; preferring the host's keeps the answer right on an install
    /// that has both, which `KernelArch.allCases` would not.
    private static var architecturesToProbe: [KernelArch] {
        #if arch(x86_64)
        [.amd64, .arm64]
        #else
        [.arm64, .amd64]
        #endif
    }

    /// The first kernel built with nftables: Kata 3.32.0's 6.18.35, which container 1.3.0
    /// made its recommended kernel (apple/container#2143).
    ///
    /// A floor rather than a comparison against the real recommendation, because the CLI has
    /// no command that prints which kernel it recommends. Like `MachineImageAdvisor`, this
    /// catches the common case without pretending to be authoritative, so it should drive a
    /// warning rather than a block.
    static let firstKernelWithNFTables = (major: 6, minor: 18)

    /// True when a kernel this old cannot satisfy the `iptables-nft` calls in node prep.
    static func lacksNFTables(major: Int, minor: Int) -> Bool {
        (major, minor) < (firstKernelWithNFTables.major, firstKernelWithNFTables.minor)
    }

    /// The major/minor version in an installed kernel's filename, e.g. `vmlinux-6.12.28-153`
    /// or `vmlinux-6.18.35-197-debug`. Nil when the name carries no version, which is the
    /// signal that someone chose a kernel of their own; this should not second-guess that.
    static func parseKernelVersion(fromName name: String) -> (major: Int, minor: Int)? {
        for component in name.split(separator: "-") {
            let numbers = component.split(separator: ".")
            guard numbers.count >= 2, let major = Int(numbers[0]), let minor = Int(numbers[1]) else { continue }
            return (major, minor)
        }
        return nil
    }

    /// The filename of the kernel a container actually boots. The CLI keeps the default as a
    /// symlink at `kernels/default.kernel-<arch>` pointing at the versioned binary it
    /// installed, so the link's target is the authoritative answer, not whatever else happens
    /// to be sitting in that directory.
    ///
    /// Read directly rather than through the CLI because `container system status` does not
    /// report the kernel. Orchard is not sandboxed, so the path is readable.
    ///
    /// `arch` nil means "whichever is installed": the CLI keeps one pointer per architecture
    /// and normally has only one, so assuming arm64 would report nothing at all on an amd64
    /// install, taking the warning and the named cause with it.
    static func defaultKernelName(arch: KernelArch? = nil, containerHome: URL? = nil) -> String? {
        let home = containerHome ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.container")
        for candidate in arch.map({ [$0] }) ?? Self.architecturesToProbe {
            let pointer = home.appendingPathComponent("kernels/default.kernel-\(candidate.rawValue)")
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: pointer.path) {
                return URL(fileURLWithPath: target).lastPathComponent
            }
        }
        return nil
    }

    /// The default kernel's name when it predates nftables, so `container k8s create` will
    /// abort in node prep. Nil when the kernel is new enough, when nothing is installed, or
    /// when the name carries no version.
    static func outdatedDefaultKernel(arch: KernelArch? = nil, containerHome: URL? = nil) -> String? {
        guard let name = defaultKernelName(arch: arch, containerHome: containerHome),
              let version = parseKernelVersion(fromName: name),
              lacksNFTables(major: version.major, minor: version.minor)
        else { return nil }
        return name
    }

    /// Authoritative (unlike the version floor): true when a `container k8s create` failure is
    /// the node-preparation abort. Matched on the one phrase the CLI does report accurately;
    /// the rest of its output names a step that succeeded.
    ///
    /// Deliberately not narrowed to the nftables cause. Any node-prep abort surfaces the same
    /// misleading output, and the copy in `OrchardError.k8sNodePrepFailed` only claims the
    /// kernel is at fault when the version floor agrees.
    static func outputIndicatesNodePrepFailure(_ output: String) -> Bool {
        output.lowercased().contains("node prep failed")
    }
}
