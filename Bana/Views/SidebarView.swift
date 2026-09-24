import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var query = ""

    var body: some View {
        List(selection: $store.selection) {
            if let root = store.rootURL {
                Section(root.lastPathComponent) {
                    ForEach(filtered) { project in
                        ProjectCard(runtime: store.runtime(for: project), project: project)
                            .tag(project.id)
                            .contextMenu { contextMenu(for: project) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: "جست‌وجو")
        .overlay {
            if store.rootURL == nil {
                emptyState("پوشه‌ای انتخاب نشده", button: "انتخاب پوشه…")
            } else if store.projects.isEmpty && !store.isScanning {
                emptyState("پروژه‌ای پیدا نشد", button: "انتخاب پوشهٔ دیگر…")
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
    }

    private var filtered: [Project] {
        guard !query.isEmpty else { return store.projects }
        return store.projects.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.relativePath.localizedCaseInsensitiveContains(query) }
    }

    private func emptyState(_ title: LocalizedStringKey, button: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Button(button) { store.chooseRoot() }
        }
        .padding()
    }

    @ViewBuilder
    private func contextMenu(for project: Project) -> some View {
        let active = store.runtime(for: project).status.isActive
        Button(active ? "توقف" : "اجرا") { store.toggle(project) }
        Button("باز کردن در مرورگر") { store.openInBrowser(project) }.disabled(!active)
        Divider()
        Button("نمایش در Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
    }
}
