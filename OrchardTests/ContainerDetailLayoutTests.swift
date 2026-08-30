import Foundation
import Testing
@testable import Orchard

/// The key column is sized from the longest key, so an unbounded estimate lets one
/// namespaced key crowd the value and its Show/Copy controls out of the row.
@Test("Container detail key/value tables cap the key column for long keys")
func detailKeyValueTableCapsLongKeys() {
    let longKey = "ORCHARD_UI_TEST_LONG_ENVIRONMENT_VARIABLE_KEY"

    #expect(
        DetailKeyValueTableLayout.keyColumnWidth(for: [longKey])
            == DetailKeyValueTableLayout.maximumKeyColumnWidth
    )
}

@Test("Container detail key/value tables retain natural width for short keys")
func detailKeyValueTableKeepsShortKeyWidth() {
    let width = DetailKeyValueTableLayout.keyColumnWidth(for: ["PATH"])

    #expect(width < DetailKeyValueTableLayout.maximumKeyColumnWidth)
    #expect(width > 0)
}

/// The longest key sets the column, not whichever key happens to come first.
@Test("Container detail key/value tables size from the longest key")
func detailKeyValueTableSizesFromLongestKey() {
    let mixed = DetailKeyValueTableLayout.keyColumnWidth(for: ["PATH", "HOME", "TERM_PROGRAM"])

    #expect(mixed == DetailKeyValueTableLayout.keyColumnWidth(for: ["TERM_PROGRAM"]))
}
