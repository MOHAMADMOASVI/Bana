import SwiftUI

/// Shown when nothing is selected: every project as a card.
struct OverviewGrid: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        Group {
            if store.rootURL == nil {
                welcome
            } else if store.isScanning && store.projects.isEmpty {
                ProgressView("در حال جست‌وجو…")
            } else if store.projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("پروژهٔ Laravel، PHP، Python، Node.js یا Docker پیدا نشد").foregroundStyle(.secondary)
                    Button("انتخاب پوشهٔ دیگر…") { store.chooseRoot() }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        ForEach(store.projects) { project in
                            ProjectCard(runtime: store.runtime(for: project), project: project, style: .tile)
                                .contentShape(Rectangle())
                                .onTapGesture { store.selection = project.id }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("پروژه‌ها")
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            Text("بنا").font(.title2.weight(.semibold))
            Text("پوشه‌ای را که پروژه‌هایتان در آن است انتخاب کنید.\nپروژه‌های Laravel، PHP، Python، Node.js و Docker خودکار شناخته می‌شوند.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("انتخاب پوشه…") { store.chooseRoot() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
    }
}
