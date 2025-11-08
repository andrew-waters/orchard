import SwiftUI
import AppKit

struct RegistrySettingsView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            if containerService.isRegistriesLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading registries...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if containerService.registries.isEmpty {
                VStack(spacing: 16) {
                    SwiftUI.Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Registries")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Add a registry login to pull images from private repositories.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Add Registry") {
                        showRegistryLoginDialog()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(containerService.registries) { registry in
                            registryRow(registry: registry)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Button(action: {
                showRegistryLoginDialog()
            }) {
                Label("Add Registry", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func registryRow(registry: Registry) -> some View {
        HStack {
            HStack(spacing: 12) {
                // Default indicator icon
                if registry.isDefault {
                    SwiftUI.Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                } else {
                    SwiftUI.Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(registry.server)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(registry.isDefault ? .semibold : .medium)

                    if let username = registry.username {
                        Text("User: \(username)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if registry.isDefault {
                        Text("Default Registry")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if registry.isDefault {
                    Button("Unset Default") {
                        Task {
                            await containerService.unsetDefaultRegistry()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.orange)
                    .disabled(containerService.isRegistriesLoading)
                } else {
                    Button("Set Default") {
                        Task {
                            await containerService.setDefaultRegistry(registry.server)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(containerService.isRegistriesLoading)
                }

                Button("Logout") {
                    showRegistryLogoutDialog(registry: registry.server)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.red)
                .disabled(containerService.isRegistriesLoading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(registry.isDefault ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private func showRegistryLoginDialog() {
        let alert = NSAlert()
        alert.messageText = "Registry Login"
        alert.informativeText = "Login to a container registry to access private repositories."
        alert.alertStyle = .informational

        // Create a custom view for the dialog
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 140))

        // Server field
        let serverLabel = NSTextField(labelWithString: "Registry Server:")
        serverLabel.frame = NSRect(x: 0, y: 115, width: 120, height: 20)
        let serverField = NSTextField(frame: NSRect(x: 0, y: 95, width: 400, height: 24))
        serverField.placeholderString = "docker.io, ghcr.io, registry.example.com"

        // Username field
        let usernameLabel = NSTextField(labelWithString: "Username:")
        usernameLabel.frame = NSRect(x: 0, y: 70, width: 120, height: 20)
        let usernameField = NSTextField(frame: NSRect(x: 0, y: 50, width: 400, height: 24))
        usernameField.placeholderString = "your-username"

        // Password field
        let passwordLabel = NSTextField(labelWithString: "Password:")
        passwordLabel.frame = NSRect(x: 0, y: 25, width: 120, height: 20)
        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 5, width: 400, height: 24))
        passwordField.placeholderString = "your-password or token"

        containerView.addSubview(serverLabel)
        containerView.addSubview(serverField)
        containerView.addSubview(usernameLabel)
        containerView.addSubview(usernameField)
        containerView.addSubview(passwordLabel)
        containerView.addSubview(passwordField)

        alert.accessoryView = containerView
        alert.addButton(withTitle: "Login")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let server = serverField.stringValue.trimmingCharacters(in: .whitespaces)
            let username = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
            let password = passwordField.stringValue

            if server.isEmpty || username.isEmpty || password.isEmpty {
                errorMessage = "Please fill in all fields."
                showingErrorAlert = true
                return
            }

            let request = RegistryLoginRequest(
                server: server,
                username: username,
                password: password,
                scheme: .auto
            )

            Task {
                await containerService.loginToRegistry(request)
            }
        }
    }

    private func showRegistryLogoutDialog(registry: String) {
        let alert = NSAlert()
        alert.messageText = "Registry Logout"
        alert.informativeText = "Are you sure you want to logout from '\(registry)'? You will need to login again to access private repositories."
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Logout")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            Task {
                await containerService.logoutFromRegistry(registry)
            }
        }
    }
}

struct RegistrySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RegistrySettingsView()
            .environmentObject(ContainerService())
    }
}
