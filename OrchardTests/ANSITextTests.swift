import AppKit
import Testing
@testable import Orchard

@Test("ANSIText: a line without escapes passes through untouched")
func ansiPlainPassthrough() {
    #expect(ANSIText.plain("hello world") == "hello world")
    let segments = ANSIText.segments("hello world")
    #expect(segments.count == 1)
    #expect(segments[0].text == "hello world")
    #expect(segments[0].style == .plain)
}

@Test("ANSIText: SGR color codes split the line into styled segments")
func ansiColorSegments() {
    let segments = ANSIText.segments("a \u{1B}[31mred\u{1B}[0m tail")
    #expect(segments.map(\.text) == ["a ", "red", " tail"])
    #expect(segments[0].style == .plain)
    #expect(segments[1].style.foreground != nil)
    #expect(segments[2].style == .plain)
}

@Test("ANSIText: plain() strips color codes for filtering")
func ansiPlainStripsCodes() {
    #expect(ANSIText.plain("\u{1B}[1;32mINFO\u{1B}[0m ready") == "INFO ready")
}

@Test("ANSIText: bold, italic, and underline set and clear")
func ansiTextStyles() {
    let segments = ANSIText.segments("\u{1B}[1;3;4mx\u{1B}[22;23;24my")
    #expect(segments.count == 2)
    #expect(segments[0].style.bold && segments[0].style.italic && segments[0].style.underline)
    #expect(segments[1].style == .plain)
}

@Test("ANSIText: bright colors, backgrounds, and default resets")
func ansiBrightAndBackground() {
    let segments = ANSIText.segments("\u{1B}[91;44mx\u{1B}[39;49my")
    #expect(segments[0].style.foreground != nil)
    #expect(segments[0].style.background != nil)
    #expect(segments[1].style == .plain)
}

@Test("ANSIText: 256-color and truecolor sequences parse (and their colon form)")
func ansiExtendedColors() {
    let indexed = ANSIText.segments("\u{1B}[38;5;196mx")
    #expect(indexed[0].style.foreground != nil)

    let true24 = ANSIText.segments("\u{1B}[38;2;255;128;0mx")
    #expect(true24[0].style.foreground != nil)

    let colonForm = ANSIText.segments("\u{1B}[38:5:196mx")
    #expect(colonForm[0].style.foreground != nil)

    // The extended introducer must not swallow codes that follow it.
    let followed = ANSIText.segments("\u{1B}[38;5;196;1mx")
    #expect(followed[0].style.foreground != nil)
    #expect(followed[0].style.bold)
}

@Test("ANSIText: non-SGR CSI sequences and OSC titles are stripped")
func ansiStripsOtherSequences() {
    #expect(ANSIText.plain("\u{1B}[2Kleast\u{1B}[1Award") == "leastward")
    #expect(ANSIText.plain("\u{1B}]0;window title\u{07}visible") == "visible")
    #expect(ANSIText.plain("\u{1B}]8;;https://x\u{1B}\\link") == "link")
}

@Test("ANSIText: carriage-return overwrite keeps the final content")
func ansiCarriageReturn() {
    #expect(ANSIText.plain("50%\r75%\r100%") == "100%")
    // A bare trailing \r (CRLF line endings after splitting on \n) is stripped.
    #expect(ANSIText.plain("done\r") == "done")
}

@Test("ANSIText: malformed input degrades without crashing")
func ansiMalformed() {
    #expect(ANSIText.plain("tail\u{1B}") == "tail")
    #expect(ANSIText.plain("x\u{1B}[31") == "x")          // unterminated CSI
    #expect(ANSIText.plain("x\u{1B}]0;title") == "x")     // unterminated OSC
    #expect(ANSIText.plain("\u{1B}[999mx") == "x")        // unknown SGR code
    #expect(ANSIText.plain("\u{1B}[38;5;900mx") == "x")   // out-of-range 256 index
    #expect(ANSIText.plain("") == "")
}

@Test("ANSIText: an empty SGR parameter list means reset")
func ansiEmptyParameterReset() {
    let segments = ANSIText.segments("\u{1B}[31mred\u{1B}[mplain")
    #expect(segments.count == 2)
    #expect(segments[1].style == .plain)
}
