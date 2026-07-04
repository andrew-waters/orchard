import AppKit
import SwiftUI

struct MultiContainerCardsView: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var statsService: StatsService
    let containerIds: Set<String>
    @Binding var selectedContainersBinding: Set<String>

    @State private var pendingAction: BulkAction?

    private enum BulkAction: Identifiable {
        case start, stop, remove
        var id: String {
            switch self {
            case .start: return "start"
            case .stop: return "stop"
            case .remove: return "remove"
            }
        }
    }

    private var containers: [Container] {
        containerListService.containers
            .filter { containerIds.contains($0.configuration.id) }
            .sorted { $0.configuration.id < $1.configuration.id }
    }

    private var runningIds: [String] {
        containers.filter { $0.status.lowercased() == "running" }.map { $0.configuration.id }
    }

    private var stoppedIds: [String] {
        containers.filter { $0.status.lowercased() != "running" }.map { $0.configuration.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(containers, id: \.configuration.id) { container in
                        ContainerSummaryCard(container: container) {
                            selectedContainersBinding = [container.configuration.id]
                        }
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(confirmButtonTitle(for: action), role: action == .remove ? .destructive : nil) {
                performAction(action)
            }
            Button("Cancel", role: .cancel) { }
        } message: { action in
            Text(confirmationMessage(for: action))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(containers.count) containers selected")
                .font(.headline)

            Spacer()

            if !stoppedIds.isEmpty {
                Button("Start stopped containers") {
                    pendingAction = .start
                }
            }

            if !runningIds.isEmpty {
                Button("Stop running containers") {
                    pendingAction = .stop
                }
            }

            if !stoppedIds.isEmpty {
                Button("Remove stopped containers") {
                    pendingAction = .remove
                }
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func ids(for action: BulkAction) -> [String] {
        switch action {
        case .start: return stoppedIds
        case .stop: return runningIds
        case .remove: return stoppedIds
        }
    }

    private var confirmationTitle: String {
        guard let action = pendingAction else { return "" }
        switch action {
        case .start: return "Start stopped containers?"
        case .stop: return "Stop running containers?"
        case .remove: return "Remove stopped containers?"
        }
    }

    private func confirmButtonTitle(for action: BulkAction) -> String {
        switch action {
        case .start: return "Start"
        case .stop: return "Stop"
        case .remove: return "Remove"
        }
    }

    private func confirmationMessage(for action: BulkAction) -> String {
        let affected = ids(for: action)
        let verb: String
        switch action {
        case .start: verb = "started"
        case .stop: verb = "stopped"
        case .remove: verb = "removed"
        }
        let header = "The following \(affected.count) container\(affected.count == 1 ? "" : "s") will be \(verb):"
        let list = affected.map { "• \($0)" }.joined(separator: "\n")
        let suffix = (action == .remove) ? "\n\nThis action cannot be undone." : ""
        return "\(header)\n\n\(list)\(suffix)"
    }

    private func performAction(_ action: BulkAction) {
        let targets = ids(for: action)
        Task {
            for id in targets {
                switch action {
                case .start: await containerListService.startContainer(id)
                case .stop: await containerListService.stopContainer(id)
                case .remove: await containerListService.removeContainer(id)
                }
            }
        }
    }
}

private struct ContainerSummaryCard: View {
    @EnvironmentObject var containerListService: ContainerListService
    @EnvironmentObject var statsService: StatsService
    let container: Container
    let onOpen: () -> Void

    private var isRunning: Bool { container.status.lowercased() == "running" }

    private var firstAddress: String? {
        container.networks.first?.address
    }

    private var firstHostname: String? {
        guard let h = container.networks.first?.hostname, !h.isEmpty else { return nil }
        return h.hasSuffix(".") ? String(h.dropLast()) : h
    }

    private var stats: ContainerStats? {
        statsService.containerStats.first { $0.id == container.configuration.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isRunning ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)

                Text(container.configuration.id)
                    .font(.system(.headline, design: .default))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(container.status.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (isRunning ? Color.green : Color.secondary).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundColor(isRunning ? .green : .secondary)

                Spacer()

                if isRunning {
                    Button("Stop") {
                        let id = container.configuration.id
                        Task { await containerListService.stopContainer(id) }
                    }
                } else {
                    Button("Start") {
                        let id = container.configuration.id
                        Task { await containerListService.startContainer(id) }
                    }
                }

                Button("Remove") {
                    let id = container.configuration.id
                    Task { await containerListService.removeContainer(id) }
                }
                .foregroundColor(.red)

                Button("Open") {
                    onOpen()
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(label: "Image", value: container.configuration.image.reference)
                    if let host = firstHostname {
                        InfoRow(label: "Hostname", value: host)
                    }
                    if let addr = firstAddress {
                        InfoRow(label: "Address", value: addr)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(
                        label: "CPUs",
                        value: "\(container.configuration.resources.cpus)"
                    )
                    InfoRow(
                        label: "Memory",
                        value: ByteCountFormatter().string(
                            fromByteCount: Int64(container.configuration.resources.memoryInBytes))
                    )
                    if isRunning, let stats {
                        InfoRow(label: "Mem used", value: stats.formattedMemoryUsage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}
