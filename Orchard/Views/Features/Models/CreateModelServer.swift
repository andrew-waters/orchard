import SwiftUI

/// Sheet to start a new managed model server (mlx_lm.server). Minimal by design: a model id,
/// a port, and the bind-address control that decides whether containers can reach it.
struct CreateModelServerView: View {
    @EnvironmentObject var modelServerService: ModelServerService
    @Environment(\.dismiss) private var dismiss

    @State private var model: String = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    @State private var port: String = "8080"
    /// Bind 0.0.0.0 (reachable from containers) vs 127.0.0.1 (this Mac only).
    @State private var allowContainers: Bool = true

    private var isValid: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && UInt16(port) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SwiftUI.Image(systemName: "sparkles")
                Text("New Model Server")
                    .font(.headline)
                Spacer()
            }
            .padding()
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                field(title: "Model", placeholder: "mlx-community/…", text: $model, mono: true)
                Text("A Hugging Face MLX model id. It downloads on first start, then runs on the Apple GPU.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                field(title: "Port", placeholder: "8080", text: $port)

                Toggle("Allow containers to reach it (bind 0.0.0.0)", isOn: $allowContainers)
                    .font(.subheadline)
                Text(allowContainers
                     ? "Bound to all interfaces, so containers can reach it over their network gateway."
                     : "Bound to 127.0.0.1 — reachable only from this Mac, not from containers.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Spacer()
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start Server") { startServer() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 460, height: 340)
    }

    private func field(title: String, placeholder: String, text: Binding<String>, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(mono ? .system(.body, design: .monospaced) : .body)
        }
    }

    private func startServer() {
        guard let portValue = UInt16(port) else { return }
        let host = allowContainers ? "0.0.0.0" : "127.0.0.1"
        if modelServerService.start(model: model, host: host, port: portValue) {
            dismiss()
        }
    }
}
