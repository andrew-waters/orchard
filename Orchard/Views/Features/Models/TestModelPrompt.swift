import SwiftUI

/// A lightweight chat session against a model server - send a message, keep the history, and
/// carry it forward so the model has context. Talks to the provider on the host (127.0.0.1),
/// the same endpoint detection uses. Intentionally a PoC: no streaming, no persistence.
struct TestModelPromptView: View {
    @EnvironmentObject var modelService: ModelService
    @Environment(\.dismiss) private var dismiss

    let providerName: String
    let port: UInt16
    let api: ModelAPIStyle

    @State private var model: String
    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var errorText: String?
    @State private var isSending = false

    init(providerName: String, port: UInt16, api: ModelAPIStyle, model: String) {
        self.providerName = providerName
        self.port = port
        self.api = api
        _model = State(initialValue: model)
    }

    private var canSend: Bool {
        !model.trimmingCharacters(in: .whitespaces).isEmpty
            && !input.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .frame(width: 580, height: 620)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            SwiftUI.Image(systemName: "text.bubble")
                .font(.title2)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat")
                    .font(.headline)
                Text("\(providerName) · 127.0.0.1:\(String(port))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                messages.removeAll()
                errorText = nil
            } label: {
                Label("New", systemImage: "square.and.pencil")
            }
            .disabled(messages.isEmpty || isSending)
            .help("Start a new conversation")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty && errorText == nil {
                        Text("Send a message to start the conversation. History is kept and sent back each turn, so the model has context.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if isSending {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Thinking…").font(.caption).foregroundColor(.secondary)
                        }
                        .id("thinking")
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.callout)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: isSending) {
                if isSending { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                Text(isUser ? "You" : "Assistant")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(message.content)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(
                        (isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1)),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Model")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { if canSend { send() } }
                Button("Send") { send() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSend)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        errorText = nil
        messages.append(ChatMessage(role: .user, content: text))
        input = ""
        isSending = true

        let history = messages
        let currentModel = model.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let reply = try await modelService.complete(port: port, api: api, model: currentModel, messages: history)
                messages.append(ChatMessage(role: .assistant, content: reply))
            } catch {
                errorText = error.localizedDescription
            }
            isSending = false
        }
    }
}
