import SwiftUI

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

// MARK: - Individual log pane (single container)

struct LogPaneView: View {
    let paneId: UUID
    let canClose: Bool
    let onClose: () -> Void

    @EnvironmentObject var containerService: ContainerService
    @State private var selectedContainerId: String?
    @State private var logLines: [String] = []
    @State private var filterText: String = ""
    @State private var refreshTimer: Timer?
    @State private var isLoading: Bool = false
    @State private var hasScrolledToBottom: Bool = false
    @State private var isPaused: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header: container picker + controls
            HStack(spacing: 8) {
                Picker("", selection: $selectedContainerId) {
                    Text("Select container...")
                        .tag(nil as String?)
                    ForEach(containerService.containers, id: \.configuration.id) { container in
                        HStack {
                            Circle()
                                .fill(container.status.lowercased() == "running" ? .green : .secondary)
                                .frame(width: 6, height: 6)
                            Text(container.configuration.id)
                        }
                        .tag(container.configuration.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 250)

                Spacer()

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
            .padding(.vertical, 6)

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

            // Log stream
            ScrollViewReader { proxy in
                ScrollView {
                    if isLoading && logLines.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading logs...")
                                .foregroundColor(Color(white: 0.85))
                                .padding()
                            Spacer()
                        }
                    } else if selectedContainerId == nil {
                        HStack {
                            Spacer()
                            Text("Select a container above")
                                .foregroundColor(Color(white: 0.5))
                                .padding()
                            Spacer()
                        }
                    } else if logLines.isEmpty {
                        HStack {
                            Spacer()
                            Text("No logs available")
                                .foregroundColor(Color(white: 0.5))
                                .padding()
                            Spacer()
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                                logLineView(line)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color.black.opacity(0.85))
                .onChange(of: logLines.count) {
                    if !hasScrolledToBottom && !logLines.isEmpty {
                        hasScrolledToBottom = true
                        proxy.scrollTo(displayLines.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            // Default to first running container
            selectedContainerId = containerService.containers
                .first { $0.status.lowercased() == "running" }?
                .configuration.id
            startRefresh()
        }
        .onDisappear {
            stopRefresh()
        }
        .onChange(of: selectedContainerId) {
            logLines = []
            hasScrolledToBottom = false
            Task { await fetchLogs() }
        }
    }

    private var displayLines: [String] {
        if filterText.isEmpty {
            return logLines
        }
        let search = filterText.lowercased()
        return logLines.filter { $0.lowercased().contains(search) }
    }

    @ViewBuilder
    private func logLineView(_ line: String) -> some View {
        if filterText.isEmpty {
            Text(line)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(white: 0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
        } else {
            Text(highlightMatches(in: line))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(white: 0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
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
        Task { await fetchLogs() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { await fetchLogs() }
        }
    }

    private func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func fetchLogs() async {
        guard !isPaused else { return }
        guard let cid = selectedContainerId else { return }

        if logLines.isEmpty {
            await MainActor.run { isLoading = true }
        }

        do {
            let lines = try await containerService.fetchContainerLogs(containerId: cid)

            await MainActor.run {
                logLines = lines
                isLoading = false
            }
        } catch {
            await MainActor.run {
                if logLines.isEmpty {
                    logLines = ["Error: \(error.localizedDescription)"]
                }
                isLoading = false
            }
        }
    }
}
