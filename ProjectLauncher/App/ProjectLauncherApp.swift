import SwiftUI

@main
struct ProjectLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = ProjectStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Projects Folder…") { store.chooseRoot() }
                    .keyboardShortcut("o")
                Button("Rescan Projects") { store.rescan() }
                    .keyboardShortcut("r")
                    .disabled(store.rootURL == nil)
            }
        }
    }
}
