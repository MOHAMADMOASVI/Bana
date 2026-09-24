import SwiftUI

/// Name, type icon, status badge, Start/Stop and Open in Browser. Used in the sidebar and the overview grid.
struct ProjectCard: View {
    enum Style { case row, tile }

    @EnvironmentObject private var store: ProjectStore
    @ObservedObject var runtime: ProjectRuntime
    let project: Project
    var style: Style = .row

    var body: some View {
        let type = store.type(of: project)
        switch style {
        case .row:
            HStack(spacing: 10) {
                TypeIcon(type: type, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.body.weight(.medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        StatusBadge(status: runtime.status)
                        if let port = runtime.port, runtime.status.isActive {
                            Text(":\(String(port))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 4)
                buttons
            }
            .padding(.vertical, 3)

        case .tile:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    TypeIcon(type: type, size: 34)
                    Spacer()
                    StatusBadge(status: runtime.status)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.headline).lineLimit(1)
                    Text("\(type.displayName) · \(project.relativePath)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                HStack { buttons; Spacer() }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button {
                store.toggle(project)
            } label: {
                Image(systemName: runtime.status.isActive ? "stop.fill" : "play.fill")
                    .frame(width: 14)
            }
            .help(runtime.status.isActive ? "Stop" : "Start")
            .disabled(runtime.status == .stopping)

            Button {
                store.openInBrowser(project)
            } label: {
                Image(systemName: "safari")
            }
            .help("Open in Browser")
            .disabled(runtime.status != .running || runtime.port == nil)
        }
        .buttonStyle(.borderless)
        .controlSize(style == .tile ? .regular : .small)
    }
}
