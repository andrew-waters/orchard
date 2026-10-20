import Testing
import Foundation
import MachineAPIClient
import ContainerAPIClient
@testable import Orchard

// The create form's account fields (container 1.6.0): validation of what was typed, and the
// `machine create` user options the backend parses with upstream's `Flags.MachineUser`.

@Test("Machine account: empty fields send no user options, so the host user is the default")
func machineAccountEmptyIsHostDefault() throws {
    let account = try MachineAccountSpec(userText: "", uidText: " ", gidText: "", homeText: "")

    #expect(account == MachineAccountSpec())
    #expect(account.arguments.isEmpty)
    let flags = try Flags.MachineUser.parse(account.arguments)
    #expect(flags.user == nil && flags.uid == nil && flags.gid == nil && flags.home == nil)
}

@Test("Machine account: only the fields that were filled in become options")
func machineAccountOnlyFilledFields() throws {
    #expect(try MachineAccountSpec(userText: "dev", uidText: "", gidText: "", homeText: "").arguments
            == ["--user", "dev"])
    #expect(try MachineAccountSpec(userText: "", uidText: "1500", gidText: "", homeText: "").arguments
            == ["--uid", "1500"])
    #expect(try MachineAccountSpec(userText: "", uidText: "", gidText: "1600", homeText: "").arguments
            == ["--gid", "1600"])
    #expect(try MachineAccountSpec(userText: "", uidText: "", gidText: "", homeText: "/srv/dev").arguments
            == ["--home", "/srv/dev"])
}

@Test("Machine account: every field, trimmed, round-trips through upstream's flag parsing")
func machineAccountAllFieldsParse() throws {
    let account = try MachineAccountSpec(userText: " devuser ", uidText: "1500", gidText: "1600", homeText: "/srv/devhome ")

    let flags = try Flags.MachineUser.parse(account.arguments)

    #expect(flags.user == "devuser")
    #expect(flags.uid == 1500)
    #expect(flags.gid == 1600)
    #expect(flags.home == "/srv/devhome")
}

@Test("Machine account: users that upstream would misread or that don't suit /etc/passwd are refused")
func machineAccountRejectsBadUsers() {
    // All digits reads as a UID upstream, and `:` as a GID.
    for user in ["1500", "dev:20", "dev user", "dev\nroot", "-dev", "dev/x", String(repeating: "a", count: 33)] {
        #expect(throws: MachineAccountError.self, "\(user)") {
            try MachineAccountSpec(userText: user, uidText: "", gidText: "", homeText: "")
        }
    }
    for user in ["dev", "_svc", "Dev.User-2", String(repeating: "a", count: 32)] {
        #expect(throws: Never.self, "\(user)") {
            try MachineAccountSpec(userText: user, uidText: "", gidText: "", homeText: "")
        }
    }
}

@Test("Machine account: UID and GID must be whole numbers that fit a UInt32")
func machineAccountRejectsBadIds() {
    for id in ["-1", "1.5", "abc", "4294967296"] {
        #expect(throws: MachineAccountError.self, "uid \(id)") {
            try MachineAccountSpec(userText: "", uidText: id, gidText: "", homeText: "")
        }
        #expect(throws: MachineAccountError.self, "gid \(id)") {
            try MachineAccountSpec(userText: "", uidText: "", gidText: id, homeText: "")
        }
    }
    #expect(throws: Never.self) {
        try MachineAccountSpec(userText: "", uidText: "0", gidText: "4294967295", homeText: "")
    }
}

@Test("Machine account: the home must be an absolute path other than /, with no colon")
func machineAccountRejectsBadHomes() {
    for home in ["home/dev", "~/dev", "/", "/home/a:b", "/home/a\nb"] {
        #expect(throws: MachineAccountError.self, "\(home)") {
            try MachineAccountSpec(userText: "", uidText: "", gidText: "", homeText: home)
        }
    }
}

@Test("Machine account fields are offered from container 1.6.0, and not when the version is unknown")
func supportsUserAccountByVersion() {
    for version in ["1.6.0", "1.6.1", "2.0.0"] {
        #expect(MachineService.supportsUserAccount(containerVersion: version), "\(version)")
    }
    for version in ["1.5.0", "1.5.10", "", "unknown"] {
        #expect(!MachineService.supportsUserAccount(containerVersion: version), "\(version)")
    }
    #expect(!MachineService.supportsUserAccount(containerVersion: nil))
}
