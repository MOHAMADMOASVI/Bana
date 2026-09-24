import SwiftUI

/// Shown when nothing is selected: every project as a card.
struct OverviewGrid: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        Group {
            if store.rootURL == nil {
                welcome
            } else if store.isScanning && store.projects.isEmpty {
                ProgressView("Scanning…")
            } else if store.projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("No Laravel, PHP, Python, Node.js or Docker projects found").foregroundStyle(.secondary)
                    Button("Choose Another Folder…") { store.chooseRoot() }
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
        .navigationTitle("Projects")
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
            Text("Project Launcher").font(.title2.weight(.semibold))
            Text("Choose the folder where you keep your projects.\nLaravel, PHP, Python, Node.js and Docker projects are detected automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Choose Folder…") { store.chooseRoot() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
    }
}
