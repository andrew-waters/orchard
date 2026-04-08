import SwiftUI

struct MergedLogLine: Identifiable {
    let id: Int
    let containerId: String
    let text: String
    let color: Color
}

// MARK: - Multi-pane log viewer window

struct MultiLogView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var paneIds: [UUID] = [UUID()]
    @State private var splitVertical: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Log Viewer")
                    .font(.headline)

                Spacer()

                if paneIds.count > 1 {
                    Button(action: { splitVertical.toggle() }) {
                        SwiftUI.Image(systemName: splitVertical ? "rectangle.split.2x1" : "rectangle.split.1x2")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help(splitVertical ? "Switch to horizontal split" : "Switch to vertical split")
                }

                Button(action: addPane) {
                    Label("Split", systemImage: "rectangle.split.1x2")
                }
                .buttonStyle(.borderless)
                .help("Add a log pane")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Panes
            if paneIds.count == 1 {
                LogPaneView(paneId: paneIds[0], canClose: false, onClose: {})
                    .environmentObject(containerService)
            } else if splitVertical {
                VSplitView {
                    ForEach(paneIds, id: \.self) { paneId in
                        LogPaneView(paneId: paneId, canClose: true) {
                            removePane(paneId)
                        }
                        .environmentObject(containerService)
                        .frame(minHeight: 200)
                    }
                }
            } else {
                HSplitView {
                    ForEach(paneIds, id: \.self) { paneId in
                        LogPaneView(paneId: paneId, canClose: true) {
                            removePane(paneId)
                        }
                        .environmentObject(containerService)
                        .frame(minWidth: 300)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    private func addPane() {
        withAnimation {
            paneIds.append(UUID())
        }
    }

    private func removePane(_ id: UUID) {
        withAnimation {
            paneIds.removeAll { $0 == id }
            if paneIds.isEmpty {
                paneIds = [UUID()]
            }
        }
    }
}

// MARK: - Individual log pane

struct LogPaneView: View {
    let paneId: UUID
    let canClose: Bool
    let onClose: () -> Void

    @EnvironmentObject var containerService: ContainerService
    @State private var selectedContainerIds: Set<String> = []
    @State private var mergedLines: [MergedLogLine] = []
    @State private var filterText: String = ""
    @State private var refreshTimer: Timer?
    @State private var isLoading: Bool = false
    @State private var hasScrolledToBottom: Bool = false
    @State private var isPaused: Bool = false

    private static let palette: [Color] = [.blue, .orange, .purple, .pink, .cyan, .yellow, .mint, .indigo]
    private static let maxLines = 5000

    private func colorFor(_ containerId: String) -> Color {
        let allIds = containerService.containers.map(\.configuration.id).sorted()
        let index = allIds.firstIndex(of: containerId) ?? 0
        return Self.palette[index % Self.palette.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Container picker bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(containerService.containers, id: \.configuration.id) { container in
                        let cid = container.configuration.id
                        let isSelected = selectedContainerIds.contains(cid)
                        let color = colorFor(cid)

                        Button(action: {
                            if isSelected {
                                selectedContainerIds.remove(cid)
                            } else {
                                selectedContainerIds.insert(cid)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                                Text(cid)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? color.opacity(0.2) : Color.clear)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isSelected ? color.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button("All") {
                        selectedContainerIds = Set(containerService.containers.map(\.configuration.id))
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderless)

                    Button("None") {
                        selectedContainerIds.removeAll()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderless)

                    Divider()
                        .frame(height: 16)

                    Button(action: { isPaused.toggle() }) {
                        SwiftUI.Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .foregroundColor(isPaused ? .orange : .secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help(isPaused ? "Resume log refresh" : "Pause log refresh")

                    if canClose {
                        Button(action: onClose) {
                            SwiftUI.Image(systemName: "xmark")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Close this pane")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            // Filter bar
            HStack {
                SwiftUI.Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Filter logs...", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !filterText.isEmpty {
                    Text("\(displayLines.count) matches")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { filterText = "" }) {
                        SwiftUI.Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Merged log stream
            ScrollViewReader { proxy in
                ScrollView {
                    if isLoading && mergedLines.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading logs...")
                                .foregroundColor(Color(white: 0.85))
                                .padding()
                            Spacer()
                        }
                    } else if mergedLines.isEmpty {
                        HStack {
                            Spacer()
                            Text(selectedContainerIds.isEmpty ? "Select containers above" : "No logs available")
                                .foregroundColor(Color(white: 0.5))
                                .padding()
                            Spacer()
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(displayLines) { line in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(line.color)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 4)

                                    Text(line.containerId)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(line.color)
                                        .frame(width: 120, alignment: .leading)
                                        .lineLimit(1)

                                    if filterText.isEmpty {
                                        Text(line.text)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(Color(white: 0.85))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text(highlightMatches(in: line.text))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(Color(white: 0.85))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .background(Color.black.opacity(0.85))
                .onChange(of: mergedLines.count) {
                    if !hasScrolledToBottom && !mergedLines.isEmpty {
                        hasScrolledToBottom = true
                        if let lastId = displayLines.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .onAppear {
            selectedContainerIds = Set(
                containerService.containers
                    .filter { $0.status.lowercased() == "running" }
                    .map(\.configuration.id)
            )
            startRefresh()
        }
        .onDisappear {
            stopRefresh()
        }
        .onChange(of: selectedContainerIds) {
            Task { await fetchAllLogs() }
        }
    }

    private var displayLines: [MergedLogLine] {
        if filterText.isEmpty {
            return mergedLines
        }
        let search = filterText.lowercased()
        return mergedLines.filter {
            $0.text.lowercased().contains(search) || $0.containerId.lowercased().contains(search)
        }
    }

    private func highlightMatches(in text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let searchLower = filterText.lowercased()
        let textLower = text.lowercased()

        var searchRange = textLower.startIndex..<textLower.endIndex
        while let range = textLower.range(of: searchLower, range: searchRange) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .yellow.opacity(0.7)
                attributed[attrRange].foregroundColor = .black
            }
            searchRange = range.upperBound..<textLower.endIndex
        }
        return attributed
    }

    private func startRefresh() {
        Task { await fetchAllLogs() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { await fetchAllLogs() }
        }
    }

    private func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func fetchAllLogs() async {
        guard !isPaused else { return }
        let ids = selectedContainerIds
        guard !ids.isEmpty else {
            await MainActor.run { mergedLines = [] }
            return
        }

        if mergedLines.isEmpty {
            await MainActor.run { isLoading = true }
        }

        let sortedIds = ids.sorted()
        var allLines: [MergedLogLine] = []
        var lineIndex = 0

        for cid in sortedIds {
            let color = colorFor(cid)
            let linesPerContainer = Self.maxLines / max(sortedIds.count, 1)

            do {
                let lines = try await containerService.fetchContainerLogs(
                    containerId: cid,
                    tailLines: linesPerContainer
                )
                for text in lines where !text.isEmpty {
                    allLines.append(MergedLogLine(id: lineIndex, containerId: cid, text: text, color: color))
                    lineIndex += 1
                }
            } catch {
                allLines.append(MergedLogLine(id: lineIndex, containerId: cid, text: "Error: \(error.localizedDescription)", color: .red))
                lineIndex += 1
            }
        }

        if allLines.count > Self.maxLines {
            allLines = Array(allLines.suffix(Self.maxLines))
        }

        await MainActor.run {
            mergedLines = allLines
            isLoading = false
        }
    }
}
