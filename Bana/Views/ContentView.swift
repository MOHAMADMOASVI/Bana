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
            ToolbarItem(placement: .primaryAction) {
                // One group: the three buttons stay side by side instead of folding into the overflow menu.
                ControlGroup {
                    Button { store.rescan() } label: { Label(tr("اسکن دوباره", "Rescan"), systemImage: "arrow.clockwise") }
                        .help(tr("اسکن دوبارهٔ پروژه‌ها (⌘R)", "Rescan projects (⌘R)"))
                        .disabled(store.rootURL == nil)
                    Button { store.chooseRoot() } label: { Label(tr("انتخاب پوشه", "Choose Folder"), systemImage: "folder") }
                        .help(tr("انتخاب پوشهٔ پروژه‌ها (⌘O)", "Choose projects folder (⌘O)"))
                    SettingsButton()
                }
                .controlGroupStyle(.navigation)
            }
            if store.isScanning {
                ToolbarItem(placement: .primaryAction) { ProgressView().controlSize(.small) }
            }
        }
    }
}
