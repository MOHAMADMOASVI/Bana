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
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name).font(.body.weight(.medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        StatusBadge(status: runtime.status)
                        if let port = runtime.port, runtime.status.isActive {
                            Text(":\(String(port))").ltr().font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 4)
                buttons
            }
            .padding(.vertical, 4)

        case .tile:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    TypeIcon(type: type, size: 38)
                    Spacer()
                    StatusBadge(status: runtime.status)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name).font(.headline).lineLimit(1)
                    Text(project.displayPath)
                        .ltr()
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Divider()
                HStack {
                    Text(type.displayName).font(.caption.weight(.medium)).foregroundStyle(type.tint)
                    Spacer()
                    buttons
                }
            }
            .card()
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                store.openInBrowser(project)
            } label: {
                Image(systemName: "safari")
            }
            .help(tr("باز کردن در مرورگر", "Open in Browser"))
            .disabled(runtime.status != .running || runtime.port == nil)

            Button {
                store.toggle(project)
            } label: {
                Image(systemName: runtime.status.isActive ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: style == .tile ? 20 : 17))
                    .foregroundStyle(runtime.status.isActive ? Color.red : Color.accentColor)
            }
            .help(runtime.status.isActive ? tr("توقف", "Stop") : tr("اجرا", "Start"))
            .disabled(runtime.status == .stopping)
        }
        .buttonStyle(.borderless)
    }
}
