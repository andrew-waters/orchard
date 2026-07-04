import SwiftUI

struct AddDomainView: View {
    @EnvironmentObject var dnsService: DNSService
    @Environment(\.dismiss) private var dismiss
    @State private var domainName: String = ""
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

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
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
        .frame(width: 500, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func createDomain() {
        let trimmedDomain = domainName.trimmingCharacters(in: .whitespaces)

        guard !trimmedDomain.isEmpty else { return }
        guard isValidDomainName(trimmedDomain) else {
            validationError = "Invalid domain name format."
            return
        }

        validationError = nil
        isCreating = true

        Task {
            let created = await dnsService.create(trimmedDomain)

            await MainActor.run {
                isCreating = false
                if created {
                    dismiss()
                }
            }
        }
    }

    private func isValidDomainName(_ domain: String) -> Bool {
        let domainRegex = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", domainRegex)
        return predicate.evaluate(with: domain)
    }
}
