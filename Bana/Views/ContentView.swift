import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let project = store.project(withID: store.selection) {
                ProjectDetailView(project: project, runtime: store.runtime(for: project))
                    .id(project.id)
            } else {
                OverviewGrid()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isScanning { ProgressView().controlSize(.small) }
                Button { store.rescan() } label: { Label("اسکن دوباره", systemImage: "arrow.clockwise") }
                    .help("اسکن دوبارهٔ پروژه‌ها (⌘R)")
                    .disabled(store.rootURL == nil)
                Button { store.chooseRoot() } label: { Label("انتخاب پوشه", systemImage: "folder") }
                    .help("انتخاب پوشهٔ پروژه‌ها (⌘O)")
            }
        }
    }
}
