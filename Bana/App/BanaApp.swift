import SwiftUI

@main
struct BanaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = ProjectStore.shared
    // Re-evaluates the menu titles when the language changes.
    @AppStorage(AppLanguage.key) private var language = AppLanguage.fa.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .localizedUI()
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1140, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("انتخاب پوشهٔ پروژه‌ها…", "Choose Projects Folder…")) { store.chooseRoot() }
                    .keyboardShortcut("o")
                Button(tr("اسکن دوبارهٔ پروژه‌ها", "Rescan Projects")) { store.rescan() }
                    .keyboardShortcut("r")
                    .disabled(store.rootURL == nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .localizedUI()
        }
    }
}
