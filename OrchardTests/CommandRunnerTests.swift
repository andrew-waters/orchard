import Testing
@testable import Orchard

// The admin script must treat every user-supplied token as literal text — a space,
// quote, or command substitution must never break out of the quoting and execute as root.

@Test("adminScript: a plain command is single-quoted per token")
func adminScriptPlain() {
    let script = SystemCommandRunner.adminScript(program: "/usr/local/bin/container", arguments: ["system", "start"])
    #expect(script == "do shell script \"'/usr/local/bin/container' 'system' 'start'\" with administrator privileges")
}

@Test("adminScript: spaces stay inside the quoted token")
func adminScriptSpace() {
    let script = SystemCommandRunner.adminScript(program: "/opt/my apps/container", arguments: ["dns", "create", "my domain"])
    #expect(script.contains("'/opt/my apps/container'"))
    #expect(script.contains("'my domain'"))
}

@Test("adminScript: a double quote is shell-quoted then AppleScript-escaped")
func adminScriptDoubleQuote() {
    let script = SystemCommandRunner.adminScript(program: "/bin/c", arguments: ["a\"b"])
    // Inside single quotes for the shell, and the " escaped for the AppleScript literal.
    #expect(script.contains("'a\\\"b'"))
}

@Test("adminScript: a single quote uses the '\\'' sequence, backslash-escaped for AppleScript")
func adminScriptSingleQuote() {
    let script = SystemCommandRunner.adminScript(program: "/bin/c", arguments: ["a'b"])
    // shellQuote produces 'a'\''b'; the backslash is doubled for the AppleScript literal.
    #expect(script.contains("'a'\\\\''b'"))
}

@Test("adminScript: command substitution is inert (kept inside single quotes)")
func adminScriptCommandSubstitution() {
    let script = SystemCommandRunner.adminScript(program: "/bin/c", arguments: ["$(whoami)"])
    #expect(script.contains("'$(whoami)'"))
    // No unquoted $(: the substitution can't run.
    #expect(!script.contains(" $(whoami)"))
}
