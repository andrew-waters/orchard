import Testing
@testable import Orchard

@MainActor
@Test("AlertCenter: error(message) sets the current alert")
func alertCenterErrorMessage() {
    let center = AlertCenter()
    #expect(center.current == nil)
    center.error("boom")
    #expect(center.current?.message == "boom")
}

@MainActor
@Test("AlertCenter: error(OrchardError) uses the error's description")
func alertCenterErrorTyped() {
    let center = AlertCenter()
    center.error(OrchardError.containerNotFound(id: "web"))
    #expect(center.current?.message.contains("web") == true)
}

@MainActor
@Test("AlertCenter: dismiss clears the current alert")
func alertCenterDismiss() {
    let center = AlertCenter()
    center.error("boom")
    center.dismiss()
    #expect(center.current == nil)
}
