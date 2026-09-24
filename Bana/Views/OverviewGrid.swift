import SwiftUI

/// Shown when nothing is selected: every project as a card.
struct OverviewGrid: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        Group {
            if store.rootURL == nil {
                welcome
            } else if store.isScanning && store.projects.isEmpty {
                ProgressView(tr("در حال جست‌وجو…", "Scanning…"))
            } else if store.projects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text(tr("پروژهٔ Laravel، PHP، Python، Node.js یا Docker پیدا نشد", "No Laravel, PHP, Python, Node.js or Docker projects found"))
                        .foregroundStyle(.secondary)
                    Button(tr("انتخاب پوشهٔ دیگر…", "Choose Another Folder…")) { store.chooseRoot() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(tr("پروژه‌ها", "Projects")).font(.largeTitle.weight(.bold))
                            Text(summary).foregroundStyle(.secondary)
                            Spacer()
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                            ForEach(store.projects) { project in
                                ProjectCard(runtime: store.runtime(for: project), project: project, style: .tile)
                                    .contentShape(Rectangle())
                                    .onTapGesture { store.selection = project.id }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(tr("بنا", "Bana"))
    }

    private var summary: String {
        let total = store.projects.count, running = store.runningCount
        return running > 0
            ? tr("\(num(total)) پروژه · \(num(running)) در حال اجرا", "\(total) projects · \(running) running")
            : tr("\(num(total)) پروژه", "\(total) projects")
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image("BanaLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 96)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            Text(tr("به بنا خوش آمدید", "Welcome to Bana")).font(.title.weight(.semibold))
            Text(tr("پوشه‌ای را که پروژه‌هایتان در آن است انتخاب کنید.\nپروژه‌های Laravel، PHP، Python، Node.js و Docker خودکار شناخته می‌شوند.",
                    "Choose the folder where you keep your projects.\nLaravel, PHP, Python, Node.js and Docker projects are detected automatically."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(tr("انتخاب پوشه…", "Choose Folder…")) { store.chooseRoot() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                SettingsButton()
            }
            .controlSize(.large)
        }
        .padding(40)
    }
}
