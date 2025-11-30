import SwiftUI
import Foundation

struct LogsView: View {
    let containerId: String
    @EnvironmentObject var containerService: ContainerService
    @State private var logs: String = ""
    @State private var isLoading: Bool = false
    @State private var autoScroll: Bool = true
    @State private var refreshTimer: Timer?
    @State private var lastLogSize: Int = 0
    @State private var filterText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with controls
            HStack {
                Text("Logs")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(SwitchToggleStyle())

                Button(action: clearLogs) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Filter section
            HStack {
                SwiftUI.Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter logs...", text: $filterText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                if !filterText.isEmpty {
                    Text("\(matchCount) matches")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        filterText = ""
                    }) {
                        SwiftUI.Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Logs content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if isLoading && logs.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView("Loading logs...")
                                    .padding()
                                Spacer()
                            }
                        } else if logs.isEmpty {
                            HStack {
                                Spacer()
                                Text("No logs available")
                                    .foregroundColor(.secondary)
                                    .padding()
                                Spacer()
                            }
                        } else {
                            highlightedLogsView
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("logs-bottom")
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: logs) {
                    if autoScroll {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("logs-bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: filterText) {
                    if autoScroll {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("logs-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .onAppear {
            startLogRefresh()
        }
        .onDisappear {
            stopLogRefresh()
        }
    }

    private func startLogRefresh() {
        refreshLogs()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshLogs()
        }
    }

    private func stopLogRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshLogs() {
        Task {
            await fetchLogs()
        }
    }

    private func fetchLogs() async {
        await MainActor.run {
            isLoading = true
        }

        do {
            let newLogs = try await containerService.fetchContainerLogs(containerId: containerId)

            await MainActor.run {
                // Only update if logs have changed
                if newLogs != logs {
                    logs = newLogs
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                logs = "Error fetching logs: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func clearLogs() {
        logs = ""
        lastLogSize = 0
    }

    private var highlightedLogsView: some View {
        let displayLogs = filteredLogs

        return Text(createAttributedString(from: displayLogs, searchText: filterText))
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
    }

    private var filteredLogs: String {
        if filterText.isEmpty {
            return logs
        }

        let lines = logs.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            line.lowercased().contains(filterText.lowercased())
        }

        return filteredLines.joined(separator: "\n")
    }

    private var matchCount: Int {
        if filterText.isEmpty {
            return 0
        }

        let lines = logs.components(separatedBy: .newlines)
        return lines.filter { line in
            line.lowercased().contains(filterText.lowercased())
        }.count
    }

    private func createAttributedString(from text: String, searchText: String) -> AttributedString {
        var attributedString = AttributedString(text)

        guard !searchText.isEmpty else {
            return attributedString
        }

        let searchLower = searchText.lowercased()
        let textLower = text.lowercased()

        var searchRange = textLower.startIndex..<textLower.endIndex

        while let range = textLower.range(of: searchLower, range: searchRange) {
            let attributedRange = Range(range, in: attributedString)!
            attributedString[attributedRange].backgroundColor = .yellow.opacity(0.7)
            attributedString[attributedRange].foregroundColor = .black

            searchRange = range.upperBound..<textLower.endIndex
        }

        return attributedString
    }
}

struct LogsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("LogsView Preview")
                .font(.headline)
            Text("Features:")
                .font(.subheadline)
            VStack(alignment: .leading) {
                Text("• Real-time log streaming every second")
                Text("• Text filter with yellow highlighting")
                Text("• Auto-scroll toggle")
                Text("• Clear logs button")
                Text("• Match counter")
                Text("• Case-insensitive search")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}
