import SwiftUI

/// App settings (⌘,): language, appearance, projects folder, hosting output.
struct SettingsView: View {
    @EnvironmentObject private var store: ProjectStore
    @AppStorage(AppLanguage.key) private var language = AppLanguage.fa.rawValue
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue
    @AppStorage(HostingJob.outputKey) private var hostingOutput = ExecutableLocator.realHome + "/Desktop"

    var body: some View {
        Form {
            Section {
                Picker(tr("زبان", "Language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Picker(tr("ظاهر", "Appearance"), selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(tr("عمومی", "General"))
            }

            Section {
                folderRow(title: tr("پوشهٔ پروژه‌ها", "Projects folder"),
                          path: store.rootURL?.path,
                          placeholder: tr("انتخاب نشده", "Not chosen")) { store.chooseRoot() }
                if store.rootURL != nil {
                    LabeledContent(tr("پروژه‌های پیدا‌شده", "Projects found")) {
                        HStack {
                            Text(num(store.projects.count)).monospacedDigit()
                            Button(tr("اسکن دوباره", "Rescan")) { store.rescan() }.controlSize(.small)
                        }
                    }
                }
            } header: {
                Text(tr("پروژه‌ها", "Projects"))
            } footer: {
                Text(tr("تا پنج سطح زیر این پوشه جست‌وجو می‌شود.", "Searched up to five levels below this folder."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                folderRow(title: tr("محل ذخیرهٔ بسته‌ها", "Save packages to"),
                          path: hostingOutput, placeholder: "") { chooseHostingOutput() }
            } header: {
                Text(tr("آماده‌سازی هاست", "Prepare for Hosting"))
            }

            Section {
                HStack(spacing: 14) {
                    Image("BanaLogo").resizable().scaledToFit().frame(height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("بنا", "Bana")).font(.headline)
                        Text(tr("اجرای پروژه‌های لوکال و آماده‌سازی برای هاست", "Run local projects and prepare them for hosting"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(tr("نسخهٔ", "Version") + " " + version).ltr().font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: appearance) { _ in AppAppearance.current.apply() }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func folderRow(title: String, path: String?, placeholder: String, choose: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(path.map { $0.replacingOccurrences(of: ExecutableLocator.realHome, with: "~") } ?? placeholder)
                    .ltr()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.head)
                    .help(path ?? "")
                Button(tr("تغییر…", "Change…"), action: choose).controlSize(.small)
            }
        }
    }

    private func chooseHostingOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: hostingOutput)
        panel.prompt = tr("انتخاب", "Choose")
        if panel.runModal() == .OK, let url = panel.url { hostingOutput = url.path }
    }
}
