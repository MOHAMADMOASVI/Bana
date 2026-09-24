import SwiftUI

/// Gear button that opens the Settings window (same as ⌘,).
struct SettingsButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { label }
                .help(tr("تنظیمات برنامه (⌘,)", "Settings (⌘,)"))
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: { label }
                .help(tr("تنظیمات برنامه (⌘,)", "Settings (⌘,)"))
        }
    }

    private var label: some View {
        Label(tr("تنظیمات", "Settings"), systemImage: "gearshape")
    }
}
