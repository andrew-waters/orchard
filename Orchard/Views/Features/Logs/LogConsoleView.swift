import AppKit
import SwiftUI

/// The log console shared by the container detail Logs tab and the log viewer
/// window: one selectable NSTextView over the whole log, so selection and ⌘C
/// span lines (per-line SwiftUI `Text` scopes selection to a single line), with
/// ANSI SGR colors rendered via `ANSIText`.
///
/// `lines` are the raw (escape-carrying) lines to show, already filtered by the
/// caller; `filterText` is only used to paint match highlights.
struct LogConsoleView: NSViewRepresentable {
    let lines: [String]
    let filterText: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false

        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 4)
        textView.textContainer?.widthTracksTextView = true

        context.coordinator.render(lines: lines, filter: filterText, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.render(lines: lines, filter: filterText, in: scrollView)
    }

    @MainActor
    final class Coordinator {
        private var renderedLines: [String] = []
        private var renderedFilter = ""
        private var hasRendered = false
        /// Per-line render cache. The 2s poll replaces the whole array with
        /// mostly identical strings; caching by content means only new lines
        /// get parsed on each tick.
        private var lineCache: [String: NSAttributedString] = [:]

        func render(lines: [String], filter: String, in scrollView: NSScrollView) {
            // Skipping identical content is also what preserves the user's
            // selection across poll ticks in the common no-new-output case.
            guard lines != renderedLines || filter != renderedFilter else { return }
            guard let textView = scrollView.documentView as? NSTextView else { return }

            let followTail = !hasRendered || isNearBottom(scrollView)
            let output = NSMutableAttributedString()
            var freshCache: [String: NSAttributedString] = [:]
            freshCache.reserveCapacity(lines.count)

            for (index, line) in lines.enumerated() {
                let rendered = freshCache[line] ?? lineCache[line] ?? Self.renderLine(line)
                freshCache[line] = rendered
                let mutable = filter.isEmpty ? nil : highlighted(rendered, filter: filter)
                output.append(mutable ?? rendered)
                if index < lines.count - 1 {
                    output.append(Self.newline)
                }
            }

            textView.textStorage?.setAttributedString(output)
            renderedLines = lines
            renderedFilter = filter
            lineCache = freshCache
            hasRendered = true

            if followTail {
                textView.scrollToEndOfDocument(nil)
            }
        }

        /// Whether the view is scrolled to (or within a line or two of) the end,
        /// in which case a refresh keeps following the tail; a user who has
        /// scrolled up to read stays put.
        private func isNearBottom(_ scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else { return true }
            let visible = scrollView.contentView.documentVisibleRect
            return visible.maxY >= documentView.bounds.maxY - 30
        }

        private func highlighted(_ line: NSAttributedString, filter: String) -> NSAttributedString {
            // Search the original string case-insensitively rather than a
            // lowercased copy: full Unicode case mapping can change lengths
            // (e.g. U+0130 lowercases to two scalars), so ranges found in the
            // copy could land outside the original and crash addAttributes.
            let text = line.string
            guard text.range(of: filter, options: .caseInsensitive) != nil else { return line }

            let mutable = NSMutableAttributedString(attributedString: line)
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: filter, options: .caseInsensitive, range: searchRange) {
                let nsRange = NSRange(range, in: text)
                mutable.addAttributes([
                    .backgroundColor: NSColor.yellow.withAlphaComponent(0.7),
                    .foregroundColor: NSColor.black,
                ], range: nsRange)
                searchRange = range.upperBound..<text.endIndex
            }
            return mutable
        }

        // MARK: - Line rendering

        private static let fontSize: CGFloat = 12
        private static let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        private static let boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        private static let baseColor = NSColor(white: 0.85, alpha: 1)
        private static let newline = NSAttributedString(string: "\n", attributes: [.font: baseFont])

        private static func renderLine(_ line: String) -> NSAttributedString {
            let segments = ANSIText.segments(line)
            let rendered = NSMutableAttributedString()
            for segment in segments {
                rendered.append(NSAttributedString(string: segment.text, attributes: attributes(for: segment.style)))
            }
            if rendered.length == 0 {
                // A blank line still needs the font so line height stays uniform.
                return NSAttributedString(string: "", attributes: [.font: baseFont])
            }
            return rendered
        }

        private static func attributes(for style: ANSIText.Style) -> [NSAttributedString.Key: Any] {
            var font = style.bold ? boldFont : baseFont
            if style.italic {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: style.foreground ?? baseColor,
            ]
            if let background = style.background {
                attributes[.backgroundColor] = background
            }
            if style.underline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            return attributes
        }
    }
}
