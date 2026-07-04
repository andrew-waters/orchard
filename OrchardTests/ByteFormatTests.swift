import Testing
import Foundation
@testable import Orchard

// ByteFormat delegates to ByteCountFormatter (locale/OS-dependent output), so we assert
// only robust invariants, not exact strings.

@Test("ByteFormat: produces non-empty output and Int/Int64 overloads agree")
func byteFormatInvariants() {
    #expect(!ByteFormat.string(0).isEmpty)
    #expect(!ByteFormat.string(1_500_000).isEmpty)
    #expect(ByteFormat.string(1_500_000) == ByteFormat.string(Int64(1_500_000)))
}
