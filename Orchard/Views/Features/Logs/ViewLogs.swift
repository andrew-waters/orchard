import SwiftUI
import Foundation

struct LogsView: View {
    let containerId: String
    @EnvironmentObject var containerService: ContainerService
    @State private var logLines: [String] = []
    @State private var isLoading: Bool = false
    @State private var refreshTimer: Timer?
    @State private var filterText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with controls
            HStack {
                Text("Logs")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("\(displayLines.count) lines")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
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
                    Text("\(displayLines.count) matches")
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
                ScrollView {
                    if isLoading && logLines.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Loading logs...")
                                .padding()
                            Spacer()
                        }
                    } else if logLines.isEmpty {
                        HStack {
                            Spacer()
                            Text("No logs available")
                                .foregroundColor(.secondary)
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
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color.black.opacity(0.85))
        }
        .onAppear {
            startLogRefresh()
        }
        .onDisappear {
            stopLogRefresh()
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

    private func highlightMatches(in line: String) -> AttributedString {
        var attributed = AttributedString(line)
        let searchLower = filterText.lowercased()
        let lineLower = line.lowercased()

        var searchRange = lineLower.startIndex..<lineLower.endIndex
        while let range = lineLower.range(of: searchLower, range: searchRange) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .yellow.opacity(0.7)
                attributed[attrRange].foregroundColor = .black
            }
            searchRange = range.upperBound..<lineLower.endIndex
        }

        return attributed
    }

    private func startLogRefresh() {
        fetchLogsAsync()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            fetchLogsAsync()
        }
    }

    private func stopLogRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func fetchLogsAsync() {
        Task {
            await fetchLogs()
        }
    }

    private func fetchLogs() async {
        if logLines.isEmpty {
            await MainActor.run { isLoading = true }
        }

        do {
            let newLines = try await containerService.fetchContainerLogs(containerId: containerId)

            await MainActor.run {
                logLines = newLines
                isLoading = false
            }
        } catch {
            await MainActor.run {
                if logLines.isEmpty {
                    logLines = ["Error fetching logs: \(error.localizedDescription)"]
                }
                isLoading = false
            }
        }
    }

}
