import SwiftUI

struct AddNetworkView: View {
    @EnvironmentObject var containerService: ContainerService
    @Environment(\.dismiss) private var dismiss
    @State private var networkName: String = ""
    @State private var subnet: String = ""
    @State private var labels: [NetworkLabel] = []
    @State private var isCreating: Bool = false

    struct NetworkLabel: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var value: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Network")
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
                    .foregroundStyle(Color(NSColor.separatorColor)),
                alignment: .bottom
            )

            // Content
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network Name")
                        .font(.headline)

                    TextField("e.g., my-network, app-network", text: $networkName)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 32)

                    Text("Enter a unique name for the network. Use only alphanumeric characters and hyphens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Subnet (Optional)")
                        .font(.headline)

                    TextField("e.g., 192.168.1.0/24", text: $subnet)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 32)

                    Text("Specify a subnet range for the network. Leave empty to use automatic allocation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Labels (Optional)")
                            .font(.headline)

                        Spacer()

                        Button("Add Label") {
                            labels.append(NetworkLabel(key: "", value: ""))
                        }
                        .buttonStyle(.borderless)
                    }

                    if labels.isEmpty {
                        Text("No labels added")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(labels) { label in
                                HStack {
                                    TextField("Key", text: Binding(
                                        get: { label.key },
                                        set: { newValue in
                                            if let index = labels.firstIndex(where: { $0.id == label.id }) {
                                                labels[index].key = newValue
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)

                                    Text("=")
                                        .foregroundStyle(.secondary)

                                    TextField("Value", text: Binding(
                                        get: { label.value },
                                        set: { newValue in
                                            if let index = labels.firstIndex(where: { $0.id == label.id }) {
                                                labels[index].value = newValue
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)

                                    Button("Remove") {
                                        labels.removeAll { $0.id == label.id }
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                // Error/Success message display
                if let errorMessage = containerService.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.top, 8)
                } else if let successMessage = containerService.successMessage {
                    Text(successMessage)
                        .foregroundStyle(.green)
                        .font(.caption)
                        .padding(.top, 8)
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

                Button(isCreating ? "Creating..." : "Create Network") {
                    createNetwork()
                }
                .buttonStyle(.borderedProminent)
                .disabled(networkName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color(NSColor.separatorColor)),
                alignment: .top
            )
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func createNetwork() {
        let trimmedName = networkName.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else { return }
        guard isValidNetworkName(trimmedName) else {
            containerService.errorMessage = "Invalid network name. Use only alphanumeric characters and hyphens."
            return
        }

        // Validate subnet if provided
        let trimmedSubnet = subnet.trimmingCharacters(in: .whitespaces)
        if !trimmedSubnet.isEmpty && !isValidSubnet(trimmedSubnet) {
            containerService.errorMessage = "Invalid subnet format. Use CIDR notation (e.g., 192.168.1.0/24)."
            return
        }

        // Validate labels
        for label in labels {
            if label.key.trimmingCharacters(in: .whitespaces).isEmpty && !label.value.trimmingCharacters(in: .whitespaces).isEmpty {
                containerService.errorMessage = "Label key cannot be empty if value is provided."
                return
            }
        }

        isCreating = true

        // Clear any previous messages
        containerService.errorMessage = nil
        containerService.successMessage = nil

        Task {
            await containerService.createNetwork(
                name: trimmedName,
                subnet: trimmedSubnet.isEmpty ? nil : trimmedSubnet,
                labels: labels.compactMap { label in
                    let key = label.key.trimmingCharacters(in: .whitespaces)
                    let value = label.value.trimmingCharacters(in: .whitespaces)
                    return key.isEmpty ? nil : "\(key)=\(value)"
                }
            )

            await MainActor.run {
                isCreating = false

                if containerService.errorMessage == nil {
                    dismiss()
                }
            }
        }
    }

    private func isValidNetworkName(_ name: String) -> Bool {
        let networkNameRegex = "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", networkNameRegex)
        return predicate.evaluate(with: name)
    }

    private func isValidSubnet(_ subnet: String) -> Bool {
        let subnetRegex = "^([0-9]{1,3}\\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", subnetRegex)
        return predicate.evaluate(with: subnet)
    }
}
