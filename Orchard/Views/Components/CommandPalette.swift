import SwiftUI
import AppKit

/// The ⌘K command palette: a Raycast-style floating panel over the whole window that
/// fuzzy-searches every resource and exposes global + per-entity actions. It renders a
/// snapshot of entries taken when it opened (so background refresh never reshuffles
/// results mid-keystroke) and hands typed `PaletteAction`s back to `ContentView`, which
/// owns all selection state and services.
struct CommandPaletteView: View {
    let entries: [PaletteEntry]
    /// The NSWindow hosting this palette. The key monitor sees every window's events
    /// (e.g. the logs windows), so it must ignore ones from other windows.
    let hostWindow: NSWindow?
    let onAction: (PaletteAction) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private var results: [PaletteEntry] {
        CommandPaletteCatalog.rank(entries, query: query)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Click-outside dismisses.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            panel
                .padding(.top, 110)
        }
        .onAppear {
            // Drop whatever field currently holds first responder (on reopen it's the
            // middle-column filter box, re-focused by the tab switch) before claiming
            // focus - otherwise the palette loses the race and keystrokes land there.
            NSApp.keyWindow?.makeFirstResponder(nil)
            DispatchQueue.main.async { searchFocused = true }
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchField

            Divider()

            if results.isEmpty {
                VStack(spacing: 6) {
                    Text("No Results")
                        .font(.system(size: 14, weight: .medium))
                    Text("Try a resource name, or a verb like \"stop\" or \"logs\"")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                resultsList
            }

            Divider()
            footer
        }
        .frame(width: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        .accessibilityIdentifier("command-palette")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            SwiftUI.Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            TextField("Search containers, images, actions...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
                .accessibilityIdentifier("command-palette-field")
                .onChange(of: query) { _, _ in selectedIndex = 0 }
            KeyHint("esc")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        if index == 0 || results[index - 1].section != entry.section {
                            sectionHeader(entry.section)
                        }
                        PaletteRow(
                            entry: entry,
                            isSelected: index == selectedIndex,
                            onHover: { selectedIndex = index },
                            onActivate: { activate(entry) }
                        )
                        .id(entry.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 400)
            .onChange(of: selectedIndex) { _, newIndex in
                if results.indices.contains(newIndex) {
                    proxy.scrollTo(results[newIndex].id, anchor: nil)
                }
            }
        }
    }

    private func sectionHeader(_ section: PaletteSection) -> some View {
        Text(section.title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(results.count == 1 ? "1 result" : "\(results.count) results")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
            HStack(spacing: 4) {
                KeyHint("↑↓")
                Text("Navigate").font(.system(size: 10)).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                KeyHint("↩")
                Text("Open").font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Keyboard

    /// Arrows, Return and Escape via a local monitor: the focused TextField swallows
    /// arrow keys before SwiftUI key handling sees them, so intercept at the AppKit
    /// level and consume what we handle.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let hostWindow, let eventWindow = event.window, eventWindow !== hostWindow {
                return event
            }
            switch event.keyCode {
            case 126: // up
                moveSelection(-1)
                return nil
            case 125: // down
                moveSelection(1)
                return nil
            case 36, 76: // return, keypad enter
                if results.indices.contains(selectedIndex) {
                    activate(results[selectedIndex])
                }
                return nil
            case 53: // escape: clear a live query first, dismiss on the second press
                if query.isEmpty {
                    onDismiss()
                } else {
                    query = ""
                }
                return nil
            case 51: // delete: consumed while the field is still grabbing focus, so it
                      // can never edit the field behind the palette
                if !searchFocused {
                    if !query.isEmpty {
                        query.removeLast()
                    }
                    return nil
                }
                return event
            default:
                // In the instant between the palette opening and its field taking first
                // responder, plain typing would fall through to whatever field is behind
                // (e.g. the middle-column filter box). Swallow it into the query instead.
                if !searchFocused,
                   !event.modifierFlags.contains(.command),
                   let characters = event.characters,
                   !characters.isEmpty,
                   characters.allSatisfy({ !$0.isNewline && ($0.isLetter || $0.isNumber || $0.isPunctuation || $0.isSymbol || $0 == " ") }) {
                    query += characters
                    return nil
                }
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    private func activate(_ entry: PaletteEntry) {
        onDismiss()
        onAction(entry.action)
    }
}

private struct PaletteRow: View {
    let entry: PaletteEntry
    let isSelected: Bool
    let onHover: () -> Void
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isSelected ? 0.22 : 0.12))
                    .frame(width: 28, height: 28)
                    .overlay(
                        SwiftUI.Image(systemName: entry.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.accentColor)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .monospaced()
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(entry.section.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    .lineLimit(1)

                if isSelected {
                    SwiftUI.Image(systemName: "return")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in if hovering { onHover() } }
    }
}

/// A small keyboard-key chip, e.g. `esc` or `↩`.
private struct KeyHint: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium).monospaced())
            .foregroundColor(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
    }
}


/// Reports the NSWindow hosting a SwiftUI hierarchy, for window-scoped behaviour
/// (only the key window toggles its palette; the key monitor filters by window).
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
