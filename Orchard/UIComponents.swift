import AppKit
import SwiftUI
import Foundation

// MARK: - Container Components

struct ContainerImageRow: View {
    let image: ContainerImage
    @EnvironmentObject var containerService: ContainerService
    @State private var copyFeedbackStates: [String: Bool] = [:]
    @State private var showDeleteConfirmation = false

    private var imageName: String {
        // Extract the image name from the reference (e.g., "docker.io/library/alpine:3" -> "alpine")
        let components = image.reference.split(separator: "/")
        if let lastComponent = components.last {
            return String(lastComponent.split(separator: ":").first ?? lastComponent)
        }
        return image.reference
    }

    private var imageTag: String {
        // Extract the tag from the reference (e.g., "docker.io/library/alpine:3" -> "3")
        if let tagComponent = image.reference.split(separator: ":").last,
            tagComponent != image.reference.split(separator: "/").last
        {
            return String(tagComponent)
        }
        return "latest"
    }

    private var isUsedByRunningContainer: Bool {
        containerService.containers.contains { container in
            container.configuration.image.reference == image.reference &&
            container.status.lowercased() == "running"
        }
    }

    private var isUsedByAnyContainer: Bool {
        containerService.containers.contains { container in
            container.configuration.image.reference == image.reference
        }
    }

    var body: some View {
        NavigationLink(value: image.reference) {
            HStack {
                SwiftUI.Image(systemName: "square.stack.3d.up")
                    .foregroundColor(isUsedByRunningContainer ? .green : .gray)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading) {
                    Text(imageName)
                        .font(.headline)
                        .foregroundColor(isUsedByRunningContainer ? .primary : .secondary)
                    HStack {
                        Text(imageTag)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(
                            ByteCountFormatter().string(fromByteCount: Int64(image.descriptor.size))
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .contextMenu {
            Button {
                copyToClipboard(image.reference, key: "reference")
            } label: {
                HStack {
                    SwiftUI.Image(systemName: copyFeedbackStates["reference"] == true ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copyFeedbackStates["reference"] == true ? .white : .primary)
                    Text("Copy Reference")
                }
                .background(copyFeedbackStates["reference"] == true ? Color.green : Color.clear)
            }

            Button {
                copyToClipboard(image.descriptor.digest, key: "digest")
            } label: {
                HStack {
                    SwiftUI.Image(systemName: copyFeedbackStates["digest"] == true ? "checkmark" : "number")
                        .foregroundColor(copyFeedbackStates["digest"] == true ? .white : .primary)
                    Text("Copy Digest")
                }
                .background(copyFeedbackStates["digest"] == true ? Color.green : Color.clear)
            }

            Divider()

            // Only show delete if not in use by any container
            if !isUsedByAnyContainer {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        SwiftUI.Image(systemName: "trash")
                        Text("Delete Image")
                    }
                }
            } else {
                Button(role: .destructive) {
                    // Disabled - show why
                } label: {
                    HStack {
                        SwiftUI.Image(systemName: "exclamationmark.triangle")
                        Text("Image in Use")
                    }
                }
                .disabled(true)
            }
        }
        .alert("Delete Image?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await containerService.deleteImage(image.reference)
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(imageName):\(imageTag)'? This action cannot be undone.")
        }
    }

    private func copyToClipboard(_ text: String, key: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyFeedbackStates[key] = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyFeedbackStates[key] = false
        }
    }
}

struct MountRow: View {
    let mount: ContainerMount
    @EnvironmentObject var containerService: ContainerService
    @State private var copyFeedbackStates: [String: Bool] = [:]

    private var displaySource: String {
        // Show just the last component of the path for cleaner display
        URL(fileURLWithPath: mount.mount.source).lastPathComponent
    }

    private var displayDestination: String {
        // Show just the last component of the path for cleaner display
        URL(fileURLWithPath: mount.mount.destination).lastPathComponent
    }

    private var isUsedByRunningContainer: Bool {
        containerService.containers.contains { container in
            mount.containerIds.contains(container.configuration.id) &&
            container.status.lowercased() == "running"
        }
    }

    var body: some View {
        NavigationLink(value: mount.id) {
            HStack {
                SwiftUI.Image(systemName: mount.mount.type.virtiofs != nil ? "externaldrive" : "folder")
                    .foregroundColor(isUsedByRunningContainer ? .blue : .gray)
                    .frame(width: 16, height: 16)
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(displaySource)
                            .font(.headline)
                            .foregroundColor(isUsedByRunningContainer ? .primary : .secondary)
                        SwiftUI.Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(displayDestination)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .contextMenu {
            Button {
                copyToClipboard(mount.mount.source, key: "source")
            } label: {
                HStack {
                    SwiftUI.Image(systemName: copyFeedbackStates["source"] == true ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copyFeedbackStates["source"] == true ? .white : .primary)
                    Text("Copy Source Path")
                }
                .background(copyFeedbackStates["source"] == true ? Color.green : Color.clear)
            }

            Button {
                copyToClipboard(mount.mount.destination, key: "destination")
            } label: {
                HStack {
                    SwiftUI.Image(systemName: copyFeedbackStates["destination"] == true ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copyFeedbackStates["destination"] == true ? .white : .primary)
                    Text("Copy Destination Path")
                }
                .background(copyFeedbackStates["destination"] == true ? Color.green : Color.clear)
            }
        }
    }

    private func copyToClipboard(_ text: String, key: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyFeedbackStates[key] = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyFeedbackStates[key] = false
        }
    }
}

struct ContainerRow: View {
    let container: Container
    let isLoading: Bool
    let stopContainer: (String) -> Void
    let startContainer: (String) -> Void
    let removeContainer: (String) -> Void
    let openTerminal: ((String) -> Void)?
    let openTerminalBash: ((String) -> Void)?
    @State private var copyFeedbackStates: [String: Bool] = [:]

    private var networkAddress: String {
        guard !container.networks.isEmpty else {
            if container.status == "running" {
                return "No network"
            } else {
                return "Not running"
            }
        }
        return container.networks[0].address.replacingOccurrences(of: "/24", with: "")
    }

    var body: some View {
        NavigationLink(value: container.configuration.id) {
            HStack {
                SwiftUI.Image(systemName: "cube.box")
                    .foregroundColor(container.status.lowercased() == "running" ? .green : .gray)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading) {
                    Text(container.configuration.id)
                    Text(networkAddress)
                        .font(.subheadline)
                        .monospaced()
                }
            }
        }
        .padding(8)
        .contextMenu {
            if !container.networks.isEmpty {
                Button {
                    copyToClipboard(networkAddress, key: "networkAddress")
                } label: {
                    HStack {
                        SwiftUI.Image(systemName: copyFeedbackStates["networkAddress"] == true ? "checkmark" : "network")
                            .foregroundColor(copyFeedbackStates["networkAddress"] == true ? .white : .primary)
                        Text("Copy IP address")
                    }
                    .background(copyFeedbackStates["networkAddress"] == true ? Color.green : Color.clear)
                }

                Divider()
            }

            if isLoading {
                Text("Loading...")
                    .foregroundColor(.gray)
            } else if container.status.lowercased() == "running" {
                if let openTerminal = openTerminal, let openTerminalBash = openTerminalBash {
                    Menu("Open Terminal") {
                        Button {
                            openTerminal(container.configuration.id)
                        } label: {
                            HStack {
                                SwiftUI.Image(systemName: "terminal")
                                Text("Shell (sh)")
                            }
                        }

                        Button {
                            openTerminalBash(container.configuration.id)
                        } label: {
                            HStack {
                                SwiftUI.Image(systemName: "terminal.fill")
                                Text("Bash (bash)")
                            }
                        }
                    }

                    Divider()
                }

                Button("Stop Container") {
                    stopContainer(container.configuration.id)
                }
            } else {
                Button("Start Container") {
                    startContainer(container.configuration.id)
                }

                Button("Remove Container") {
                    removeContainer(container.configuration.id)
                }
            }
        }
    }

    private func copyToClipboard(_ text: String, key: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyFeedbackStates[key] = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyFeedbackStates[key] = false
        }
    }
}

// MARK: - Control Buttons

struct PowerButton: View {
    let isLoading: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            SwiftUI.Image(systemName: "power")
                .font(.system(size: 60))
                .foregroundColor(buttonColor)
                .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .help("Click to start the container system")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering && !isLoading
            }
        }
        .modifier(CursorModifier(cursor: isLoading ? .arrow : .pointingHand))
    }

    private var buttonColor: Color {
        if isLoading {
            return .white
        } else if isHovered {
            return .blue
        } else {
            return .gray
        }
    }
}

struct ContainerControlButton: View {
    let container: Container
    let isLoading: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    private var buttonState: ButtonState {
        if isLoading {
            return .loading
        } else if container.status.lowercased() == "running" {
            return .stop
        } else {
            return .start
        }
    }

    @State private var isRotating: Bool = false

    private enum ButtonState {
        case start, stop, loading

        var icon: String {
            switch self {
            case .start: return "play.fill"
            case .stop: return "stop.fill"
            case .loading: return "arrow.2.circlepath"
            }
        }

        var helpText: String {
            switch self {
            case .start: return "Start Container"
            case .stop: return "Stop Container"
            case .loading: return "Loading..."
            }
        }

        var color: Color {
            switch self {
            case .start: return .gray
            case .stop: return .gray
            case .loading: return .white
            }
        }
    }

    var body: some View {
        Button {
            switch buttonState {
            case .start:
                onStart()
            case .stop:
                onStop()
            case .loading:
                break  // No action when loading
            }
        } label: {
            SwiftUI.Image(systemName: buttonState.icon)
                .font(.system(size: 20))
                .foregroundColor(buttonState.color)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .animation(
                    buttonState == .loading
                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                        : .default,
                    value: isRotating
                )
        }
        .buttonStyle(.plain)
        .disabled(buttonState == .loading)
        .help(buttonState.helpText)
        .modifier(CursorModifier(cursor: buttonState == .loading ? .arrow : .pointingHand))
        .onChange(of: buttonState) { _, newState in
            print(
                "Container \(container.configuration.id) state changed to: \(newState), status: \(container.status), isLoading: \(isLoading)"
            )
            isRotating = (newState == .loading)
        }
        .frame(width: 30, height: 30)
    }
}

struct ContainerRemoveButton: View {
    let container: Container
    let isLoading: Bool
    let onRemove: () -> Void

    var body: some View {
        Button {
            onRemove()
        } label: {
            SwiftUI.Image(systemName: "trash.fill")
                .font(.system(size: 16))
                .foregroundColor(.gray)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || container.status.lowercased() == "running")
        .help("Remove Container")
        .modifier(
            CursorModifier(
                cursor: (isLoading || container.status.lowercased() == "running")
                    ? .arrow : .pointingHand))
    }
}

struct ContainerTerminalButton: View {
    let container: Container
    let onOpenTerminal: () -> Void
    let onOpenTerminalBash: () -> Void
    @State private var showingMenu = false

    var body: some View {
        Menu {
            Button(action: onOpenTerminal) {
                HStack {
                    SwiftUI.Image(systemName: "terminal")
                    Text("Open Terminal (sh)")
                }
            }

            Button(action: onOpenTerminalBash) {
                HStack {
                    SwiftUI.Image(systemName: "terminal.fill")
                    Text("Open Terminal (bash)")
                }
            }
        } label: {
            SwiftUI.Image(systemName: "terminal")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 30, height: 30)
        .help("Open Terminal")
    }
}

// MARK: - Utility Components

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .monospaced()
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct CopyableInfoRow: View {
    let label: String
    let value: String
    let copyValue: String?

    init(label: String, value: String, copyValue: String? = nil) {
        self.label = label
        self.value = value
        self.copyValue = copyValue
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .monospaced()
                .textSelection(.enabled)
            Spacer()
            CopyButton(text: copyValue ?? value, label: "Copy to clipboard")
        }
    }
}

struct NavigableInfoRow: View {
    let label: String
    let value: String
    let onNavigate: () -> Void

    var body: some View {
        Button(action: onNavigate) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                Text(value)
                    .font(.subheadline)
                    .monospaced()
                    .textSelection(.enabled)
                Spacer()
                SwiftUI.Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("View details")
    }
}

// MARK: - View Modifiers

struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .onHover { hovering in
                        if hovering {
                            cursor.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            )
    }
}

struct CopyButton: View {
    let text: String
    let label: String
    @State private var showingFeedback = false

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            showingFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showingFeedback = false
            }
        } label: {
            SwiftUI.Image(systemName: showingFeedback ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundColor(showingFeedback ? .white : .secondary)
                .background(showingFeedback ? Color.green : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
