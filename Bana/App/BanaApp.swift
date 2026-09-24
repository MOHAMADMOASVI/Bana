import SwiftUI

@main
struct BanaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = ProjectStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .persianUI()
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("انتخاب پوشهٔ پروژه‌ها…") { store.chooseRoot() }
                    .keyboardShortcut("o")
                Button("اسکن دوبارهٔ پروژه‌ها") { store.rescan() }
                    .keyboardShortcut("r")
                    .disabled(store.rootURL == nil)
            }
        }
    }
}
