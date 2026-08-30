import AppKit

/// Minimal ANSI/VT100 handling for log lines: SGR (color/style) sequences are
/// rendered, every other escape sequence is stripped, and a mid-line carriage
/// return keeps only the text after it, the way a terminal's overwrite reads.
///
/// Scope is deliberately one line at a time: Orchard's log views hold `[String]`
/// split on newlines, and SGR state that spans lines (a color left open at a
/// line break) is rare enough in practice that resetting per line keeps the
/// parser stateless and cacheable.
enum ANSIText {

    struct Style: Equatable {
        var bold = false
        var italic = false
        var underline = false
        var foreground: NSColor?
        var background: NSColor?

        static let plain = Style()
    }

    struct Segment: Equatable {
        let text: String
        let style: Style
    }

    // MARK: - Public surface

    /// The line with every escape sequence removed. Use this for filtering and
    /// search so a match can't land inside a color code.
    static func plain(_ line: String) -> String {
        guard line.contains("\u{1B}") || line.contains("\r") else { return line }
        return segments(line).map(\.text).joined()
    }

    /// Styled runs for one line. Segments carry only the styles the line set;
    /// the renderer decides base font and default colors.
    static func segments(_ line: String) -> [Segment] {
        var result: [Segment] = []
        var current = ""
        var style = Style.plain

        func flush() {
            if !current.isEmpty {
                result.append(Segment(text: current, style: style))
                current = ""
            }
        }

        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]

            if ch == "\u{1B}" {
                let afterEscape = line.index(after: i)
                guard afterEscape < line.endIndex else { break }

                switch line[afterEscape] {
                case "[":
                    // CSI: parameter bytes up to a final byte in 0x40-0x7E.
                    var j = line.index(after: afterEscape)
                    var params = ""
                    while j < line.endIndex, !isCSIFinalByte(line[j]) {
                        params.append(line[j])
                        j = line.index(after: j)
                    }
                    guard j < line.endIndex else { return flushed(result, current, style) }
                    if line[j] == "m" {
                        flush()
                        style = apply(parameters: params, to: style)
                    }
                    // Every other CSI verb (cursor movement, erase, …) is dropped.
                    i = line.index(after: j)

                case "]":
                    // OSC: runs to BEL or ST (ESC \).
                    var j = line.index(after: afterEscape)
                    while j < line.endIndex {
                        if line[j] == "\u{07}" {
                            j = line.index(after: j)
                            break
                        }
                        if line[j] == "\u{1B}" {
                            let k = line.index(after: j)
                            j = (k < line.endIndex && line[k] == "\\") ? line.index(after: k) : k
                            break
                        }
                        j = line.index(after: j)
                    }
                    i = j

                default:
                    // Two-character escape (ESC + one byte).
                    i = line.index(after: afterEscape)
                }
                continue
            }

            if ch == "\r" {
                let rest = line.index(after: i)
                if rest < line.endIndex {
                    // Overwrite: a progress line like "50%\r100%" shows its
                    // final state. A bare trailing \r is just stripped.
                    flush()
                    result.removeAll()
                }
                i = rest
                continue
            }

            current.append(ch)
            i = line.index(after: i)
        }

        flush()
        return result
    }

    private static func flushed(_ segments: [Segment], _ current: String, _ style: Style) -> [Segment] {
        guard !current.isEmpty else { return segments }
        return segments + [Segment(text: current, style: style)]
    }

    // MARK: - SGR parameter handling

    private static func isCSIFinalByte(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        return (0x40...0x7E).contains(scalar.value)
    }

    private static func apply(parameters: String, to style: Style) -> Style {
        var style = style
        // SGR separators are ";" per spec, but 256/truecolor emitters also use ":".
        let codes = parameters
            .split(whereSeparator: { $0 == ";" || $0 == ":" })
            .map { Int($0) ?? -1 }
        let sequence = codes.isEmpty ? [0] : codes

        var index = 0
        while index < sequence.count {
            let code = sequence[index]
            switch code {
            case 0: style = .plain
            case 1: style.bold = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 22: style.bold = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 30...37: style.foreground = palette16[code - 30]
            case 39: style.foreground = nil
            case 40...47: style.background = palette16[code - 40]
            case 49: style.background = nil
            case 90...97: style.foreground = palette16[code - 90 + 8]
            case 100...107: style.background = palette16[code - 100 + 8]
            case 38, 48:
                let (color, consumed) = extendedColor(sequence, from: index)
                if code == 38 { style.foreground = color } else { style.background = color }
                index += consumed
            default:
                break // unknown/unsupported SGR codes are ignored
            }
            index += 1
        }
        return style
    }

    /// Parses `38;5;n`, `38;2;r;g;b` (and the 48 background forms) starting at
    /// the 38/48 element. Returns the color (nil when malformed) and how many
    /// extra elements beyond the introducer were consumed.
    private static func extendedColor(_ codes: [Int], from index: Int) -> (NSColor?, Int) {
        guard index + 1 < codes.count else { return (nil, 0) }
        switch codes[index + 1] {
        case 5:
            guard index + 2 < codes.count, (0...255).contains(codes[index + 2]) else { return (nil, 1) }
            return (color256(codes[index + 2]), 2)
        case 2:
            guard index + 4 < codes.count else { return (nil, codes.count - index - 1) }
            let (r, g, b) = (codes[index + 2], codes[index + 3], codes[index + 4])
            guard [r, g, b].allSatisfy({ (0...255).contains($0) }) else { return (nil, 4) }
            return (rgb(r, g, b), 4)
        default:
            return (nil, 1)
        }
    }

    // MARK: - Palette

    /// The 16 base colors, tuned for a dark console background (VS Code's
    /// terminal palette): pure spec blue/red are illegible on near-black.
    private static let palette16: [NSColor] = [
        rgb(0x00, 0x00, 0x00), rgb(0xCD, 0x31, 0x31), rgb(0x0D, 0xBC, 0x79), rgb(0xE5, 0xE5, 0x10),
        rgb(0x24, 0x72, 0xC8), rgb(0xBC, 0x3F, 0xBC), rgb(0x11, 0xA8, 0xCD), rgb(0xE5, 0xE5, 0xE5),
        rgb(0x66, 0x66, 0x66), rgb(0xF1, 0x4C, 0x4C), rgb(0x23, 0xD1, 0x8B), rgb(0xF5, 0xF5, 0x43),
        rgb(0x3B, 0x8E, 0xEA), rgb(0xD6, 0x70, 0xD6), rgb(0x29, 0xB8, 0xDB), rgb(0xFF, 0xFF, 0xFF),
    ]

    private static func color256(_ n: Int) -> NSColor {
        if n < 16 { return palette16[n] }
        if n < 232 {
            // 6×6×6 cube; xterm levels 0, 95, 135, 175, 215, 255.
            let value = n - 16
            let levels = [0, 95, 135, 175, 215, 255]
            return rgb(levels[value / 36], levels[(value / 6) % 6], levels[value % 6])
        }
        let gray = 8 + (n - 232) * 10
        return rgb(gray, gray, gray)
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}
