import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var query = ""

    var body: some View {
        List(selection: $store.selection) {
            if let root = store.rootURL {
                Section {
                    ForEach(filtered) { project in
                        ProjectCard(runtime: store.runtime(for: project), project: project)
                            .tag(project.id)
                            .contextMenu { contextMenu(for: project) }
                    }
                } header: {
                    Text(root.lastPathComponent)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: tr("جست‌وجو", "Filter"))
        .overlay {
            if store.rootURL == nil {
                emptyState(tr("پوشه‌ای انتخاب نشده", "No folder selected"), button: tr("انتخاب پوشه…", "Choose Folder…"))
            } else if store.projects.isEmpty && !store.isScanning {
                emptyState(tr("پروژه‌ای پیدا نشد", "No projects found"), button: tr("انتخاب پوشهٔ دیگر…", "Choose Another Folder…"))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 400)
    }

    /// How many servers are up, with a one-click way to stop them all.
    @ViewBuilder
    private var footer: some View {
        let running = store.runningCount
        if running > 0 {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text(tr("\(num(running)) سرور در حال اجرا", running == 1 ? "1 server running" : "\(running) servers running"))
                        .font(.callout)
                    Spacer()
                    Button(tr("توقف همه", "Stop All")) { store.stopAll {} }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private var filtered: [Project] {
        guard !query.isEmpty else { return store.projects }
        return store.projects.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.relativePath.localizedCaseInsensitiveContains(query) }
    }

    private func emptyState(_ title: String, button: String) -> some View {
        VStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Button(button) { store.chooseRoot() }
        }
        .padding()
    }

    @ViewBuilder
    private func contextMenu(for project: Project) -> some View {
        let active = store.runtime(for: project).status.isActive
        Button(active ? tr("توقف", "Stop") : tr("اجرا", "Start")) { store.toggle(project) }
        Button(tr("باز کردن در مرورگر", "Open in Browser")) { store.openInBrowser(project) }.disabled(!active)
        Divider()
        Button(tr("نمایش در Finder", "Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
    }
}
