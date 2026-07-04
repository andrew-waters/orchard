import Testing
import Foundation
@testable import Orchard

// Pure container-name validation extracted from the Run/Edit form.

@MainActor
@Test("Name validation: empty name is treated as not-yet-an-error")
func nameValidationEmpty() throws {
    #expect(ContainerConfigForm.validationError(for: "", existing: []) == nil)
}

@MainActor
@Test("Name validation: valid names (letters/digits/._- , starting alphanumeric) pass")
func nameValidationValid() {
    for name in ["web", "web-1", "my.app_2", "1container"] {
        #expect(ContainerConfigForm.validationError(for: name, existing: []) == nil, "\(name) should be valid")
    }
}

@MainActor
@Test("Name validation: illegal characters or leading punctuation are rejected")
func nameValidationIllegal() {
    for name in ["-web", ".app", "web!", "a b", "café"] {
        #expect(ContainerConfigForm.validationError(for: name, existing: []) != nil, "\(name) should be rejected")
    }
}

@MainActor
@Test("Name validation: names longer than 63 characters are rejected")
func nameValidationTooLong() {
    let ok = String(repeating: "a", count: 63)
    let tooLong = String(repeating: "a", count: 64)
    #expect(ContainerConfigForm.validationError(for: ok, existing: []) == nil)
    #expect(ContainerConfigForm.validationError(for: tooLong, existing: [])?.contains("63 characters") == true)
}

@MainActor
@Test("Name validation: a name matching an existing container is rejected")
func nameValidationDuplicate() throws {
    let existing = [try makeContainer(id: "web", status: "running")]
    #expect(ContainerConfigForm.validationError(for: "web", existing: existing)?.contains("already exists") == true)
    #expect(ContainerConfigForm.validationError(for: "other", existing: existing) == nil)
}
