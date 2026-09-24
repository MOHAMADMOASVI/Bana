import SwiftUI

/// Live stdout/stderr, auto-scrolling to the newest line.
struct LogView: View {
    let lines: [LogLine]
    var title = "Output"
    var onClear: (() -> Void)?
    @AppStorage("logAutoScroll") private var autoScroll = true
    private static let bottomID = "log-bottom"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(.headline)
                Text("\(lines.count) lines").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: $autoScroll) { Label("Auto-scroll", systemImage: "arrow.down.to.line") }
                    .toggleStyle(.button)
                    .help("Follow new output")
                Button { copyAll() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .help("Copy log")
                if let onClear {
                    Button(action: onClear) { Label("Clear", systemImage: "trash") }
                        .help("Clear log")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .foregroundStyle(color(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: lines.last?.id) { _ in
                    guard autoScroll else { return }
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
                .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                .overlay {
                    if lines.isEmpty {
                        Text("No output yet").foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // Many servers (php -S, uvicorn) log every request to stderr, so colour by content, not by stream.
    private func color(for line: LogLine) -> Color {
        if line.stream == .system { return .secondary }
        return line.looksLikeError ? Color(nsColor: .systemRed) : .primary
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
    }
}
