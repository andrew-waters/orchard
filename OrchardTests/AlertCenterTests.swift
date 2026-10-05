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
func alertCenterDismiss() async {
    let center = AlertCenter()
    center.error("boom")
    await center.dismiss().value
    #expect(center.current == nil)
}

@MainActor
@Test("AlertCenter: an alert stops presenting as soon as it is dismissed")
func alertCenterDismissPresentsImmediately() async {
    let center = AlertCenter()
    center.error("boom")
    #expect(center.isPresenting)
    let dismissal = center.dismiss()
    // The clear itself is deferred, but the binding must already read false.
    #expect(!center.isPresenting)
    await dismissal.value
    #expect(center.current == nil)
}

@MainActor
@Test("AlertCenter: a new alert raised before a dismissal lands is kept and presented")
func alertCenterDismissKeepsNewerAlert() async {
    let center = AlertCenter()
    center.error("first")
    let dismissal = center.dismiss()
    center.error("second")
    #expect(center.isPresenting)
    await dismissal.value
    #expect(center.current?.message == "second")
    #expect(center.isPresenting)
}

@MainActor
@Test("AlertCenter: a background-source error is suppressed (no modal), user is not")
func alertCenterBackgroundSuppressed() {
    let center = AlertCenter()
    center.error("poll failed", source: .background)
    #expect(center.current == nil)                 // background never presents

    center.error("user action failed", source: .user)
    #expect(center.current?.message == "user action failed")

    // A subsequent background error must not clobber the user's alert.
    center.error("poll failed again", source: .background)
    #expect(center.current?.message == "user action failed")
}
