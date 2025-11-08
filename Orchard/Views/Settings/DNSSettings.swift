import SwiftUI
import AppKit

struct DNSSettingsView: View {
    @EnvironmentObject var containerService: ContainerService
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {

            if containerService.isDNSLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading DNS domains...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if containerService.dnsDomains.isEmpty {
                VStack(spacing: 16) {
                    SwiftUI.Image(systemName: "network.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No DNS Domains")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Add a DNS domain to enable local container networking.\nThis requires administrator privileges.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Add First Domain") {
                        showAddDNSDomainDialog()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(containerService.dnsDomains) { domain in
                            dnsRow(domain: domain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Button(action: {
                showAddDNSDomainDialog()
            }) {
                Label("Add Domain", systemImage: "plus")
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

    private func dnsRow(domain: DNSDomain) -> some View {
        HStack {
            HStack(spacing: 12) {
                // Default indicator icon
                if domain.isDefault {
                    SwiftUI.Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                } else {
                    SwiftUI.Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(domain.domain)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(domain.isDefault ? .semibold : .medium)

                    if domain.isDefault {
                        Text("Default Domain")
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
                if domain.isDefault {
                    Button("Unset Default") {
                        Task {
                            await containerService.unsetDefaultDNSDomain()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.orange)
                    .disabled(containerService.isDNSLoading)
                } else {
                    Button("Set Default") {
                        Task {
                            await containerService.setDefaultDNSDomain(domain.domain)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(containerService.isDNSLoading)
                }

                Button("Delete") {
                    showDeleteDNSDomainDialog(domain: domain.domain)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.red)
                .disabled(containerService.isDNSLoading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(domain.isDefault ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private func showAddDNSDomainDialog() {
        let alert = NSAlert()
        alert.messageText = "Add DNS Domain"
        alert.informativeText = "Enter a domain name for local container networking.\n\nThis operation requires administrator privileges and you will be prompted for your password."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "e.g., local.dev, myapp.local"
        alert.accessoryView = textField

        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let domain = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !domain.isEmpty {
                // Validate domain format
                if isValidDomainName(domain) {
                    Task {
                        await containerService.createDNSDomain(domain)
                    }
                } else {
                    errorMessage = "Invalid domain name format. Please enter a valid domain like 'local.dev' or 'myapp.local'."
                    showingErrorAlert = true
                }
            }
        }
    }

    private func showDeleteDNSDomainDialog(domain: String) {
        let alert = NSAlert()
        alert.messageText = "Delete DNS Domain"
        alert.informativeText = "Are you sure you want to delete the DNS domain '\(domain)'? This action cannot be undone and requires administrator privileges. You will be prompted for your password."
        alert.alertStyle = .warning

        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            Task {
                await containerService.deleteDNSDomain(domain)
            }
        }
    }

    private func isValidDomainName(_ domain: String) -> Bool {
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)
        return predicate.evaluate(with: domain)
    }
}

struct DNSSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        DNSSettingsView()
            .environmentObject(ContainerService())
    }
}
