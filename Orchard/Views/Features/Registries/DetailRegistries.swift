import SwiftUI

struct RegistriesDetailView: View {
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Registries cannot be listed due to limitations with container itself. To add them, you'll need to open a terminal and run the container commands. Copy your registry password to your clipboard and run:")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("pbpaste | container registry login REGISTRY_URL --username YOUR_USERNAME --password-stdin")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button(action: {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString("pbpaste | container registry login REGISTRY_URL --username YOUR_USERNAME --password-stdin", forType: .string)
                            }) {
                                SwiftUI.Image(systemName: "doc.on.clipboard")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy command to clipboard")
                        }
                    }
                }
                Spacer()
            }
            .frame(minHeight: 200)
            .padding()

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
