import Foundation
import Testing
@testable import Orchard

@Test("Container detail key/value tables preserve room for values")
func detailKeyValueTableCapsLongKeys() {
    let longEnvironmentKey = "ORCHARD_CONTAINER_DETAIL_REPRODUCTION_ENVIRONMENT_VARIABLE_WITH_A_VERY_LONG_NAME"

    #expect(
        DetailKeyValueTableLayout.keyColumnWidth(for: [longEnvironmentKey])
            == DetailKeyValueTableLayout.maximumKeyColumnWidth
    )
}

@Test("Container detail key/value tables retain natural width for short keys")
func detailKeyValueTableKeepsShortKeyWidth() {
    #expect(DetailKeyValueTableLayout.keyColumnWidth(for: ["PATH"]) == 50)
}
