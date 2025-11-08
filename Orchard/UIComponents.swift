import AppKit
import SwiftUI
import Foundation

// MARK: - Container Components

struct ContainerImageRow: View {
    let image: ContainerImage
    @EnvironmentObject var containerService: ContainerService
    @State private var copyFeedbackStates: [String: Bool] = [:]

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
            }

            if isLoading {
                Text("Loading...")
                    .foregroundColor(.gray)
            } else if container.status.lowercased() == "running" {
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

struct AppFooter: View {
    @EnvironmentObject var containerService: ContainerService
    let onOpenSettings: () -> Void

    private var containerSystemStatusColor: Color {
        return containerService.systemStatus.color
    }

    private var builderStatusColor: Color {
        return containerService.builderStatus.color
    }

    var body: some View {
        HStack {
            // Left side - Domain and Binary info
            HStack(spacing: 16) {


                // Default Domain
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(containerService.currentDefaultDomain ?? "None")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .help("Default Domain: \(containerService.currentDefaultDomain ?? "None")")

                // Binary Status
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: containerService.isUsingCustomBinary ? "terminal.fill" : "terminal")
                        .font(.system(size: 11))
                        .foregroundColor(containerService.isUsingCustomBinary ? .blue : .secondary)
                    Text(containerService.isUsingCustomBinary ? "Custom" : "Default")
                        .font(.system(size: 11))
                        .foregroundColor(containerService.isUsingCustomBinary ? .blue : .secondary)
                }
                .help("Binary Path: \(containerService.isUsingCustomBinary ? "Custom" : "Default") (\(containerService.containerBinaryPath))")
            }

            Spacer()

            // Update indicator (when available)
            if containerService.updateAvailable {
                Button(action: {
                    containerService.openReleasesPage()
                }) {
                    HStack(spacing: 4) {
                        SwiftUI.Image(systemName: "arrow.down.circle")
                            .foregroundColor(.blue)
                            .font(.system(size: 12))
                        Text("Update Available")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)
                .help("New version \(containerService.latestVersion ?? "") is available. Click to download.")
            }

            // Right side - Separate System and Builder Status
            HStack(spacing: 12) {
                // Container System Status
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "cube.box")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    Text(containerService.systemStatus.text)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .help("Container System: \(containerService.systemStatus.text)")

                // Builder Status
                HStack(spacing: 4) {
                    SwiftUI.Image(systemName: "hammer")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    Text(containerService.builderStatus.text)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .help("Builder: \(containerService.builderStatus.text)")

                // Settings Icon
                Button(action: {
                    onOpenSettings()
                }) {
                    SwiftUI.Image(systemName: "gearshape")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Open Settings")
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}
