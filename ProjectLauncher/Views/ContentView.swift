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
                Button { store.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .help("Rescan projects (⌘R)")
                    .disabled(store.rootURL == nil)
                Button { store.chooseRoot() } label: { Label("Choose Folder", systemImage: "folder") }
                    .help("Choose projects folder (⌘O)")
            }
        }
    }
}
