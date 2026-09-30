import SwiftUI

struct AddDomainView: View {
    @EnvironmentObject var dnsService: DNSService
    @Environment(\.dismiss) private var dismiss
    @State private var domainName: String = ""
    @State private var localhostAddress: String = ""
    @State private var isCreating: Bool = false
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add DNS Domain")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )

            // Content
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Domain Name")
                        .font(.headline)

                    TextField("e.g., local.dev, myapp.local", text: $domainName)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 32)

                    Text("Enter a domain name for local container networking. This requires administrator privileges.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Redirect to Host Localhost (Optional)")
                        .font(.headline)

                    TextField("e.g., 203.0.113.1", text: $localhostAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 32)

                    Text("Makes the domain resolve to this IPv4 address and redirects that address to your Mac's 127.0.0.1, so containers can reach services running on the host. Pick an address nothing else uses, such as one from 203.0.113.0/24.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
            .padding()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add Domain") {
                    createDomain()
                }
                .buttonStyle(.borderedProminent)
                .disabled(domainName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .top
            )
        }
        .frame(width: 500, height: 420)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func createDomain() {
        let trimmedDomain = domainName.trimmingCharacters(in: .whitespaces)

        guard !trimmedDomain.isEmpty else { return }
        guard InputValidation.isValidDomainName(trimmedDomain) else {
            validationError = "Invalid domain name format."
            return
        }

        let trimmedAddress = localhostAddress.trimmingCharacters(in: .whitespaces)
        guard trimmedAddress.isEmpty || InputValidation.isValidIPv4(trimmedAddress) else {
            validationError = "The localhost redirect must be an IPv4 address."
            return
        }

        validationError = nil
        isCreating = true

        Task {
            let created = await dnsService.create(
                trimmedDomain, localhost: trimmedAddress.isEmpty ? nil : trimmedAddress)

            await MainActor.run {
                isCreating = false
                if created {
                    dismiss()
                }
            }
        }
    }

}
