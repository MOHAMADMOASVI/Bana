import SwiftUI

/// “Prepare for Hosting”: explains the package, runs the build with a live log, reveals the zip.
struct HostingSheet: View {
    @ObservedObject var job: HostingJob
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                TypeIcon(type: job.type, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prepare for Hosting").font(.title3.weight(.semibold))
                    Text("\(job.project.name) · \(job.type.displayName)").foregroundStyle(.secondary)
                }
                Spacer()
                phaseBadge
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let script = job.projectScript {
                        Picker("Method", selection: $job.useProjectScript) {
                            Text("Project script (\(script.pathComponents.suffix(3).joined(separator: "/")))").tag(true)
                            Text("Bana packager").tag(false)
                        }
                        .pickerStyle(.radioGroup)
                        .disabled(job.isRunning)
                    }

                    if job.useProjectScript && job.projectScript != nil {
                        Text("The project's own build script runs in the project folder; Bana shows its output and the zip it produces.")
                            .foregroundStyle(.secondary)
                    } else {
                        section("Package layout", job.layoutDescription, symbol: "square.stack.3d.up")
                        section("Before going live", job.checks, symbol: "checklist")
                        if !job.flagged.isEmpty { reviewFiles }
                        if job.type == .laravel {
                            HStack {
                                Text("Site address").foregroundStyle(.secondary)
                                TextField("", text: $job.siteAddress, prompt: Text("example.com"))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 280)
                                    .disabled(job.isRunning)
                                if !job.siteAddress.isEmpty && HostingCopier.normalizedURL(job.siteAddress) == nil {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                        .help("Use a Latin (punycode) address like example.com")
                                }
                            }
                        }
                        if job.hasFrontendBuild && job.type != .python && job.type != .docker {
                            Toggle("Run npm run build first", isOn: $job.rebuildFrontend).disabled(job.isRunning)
                        }
                        HStack {
                            Text("Save to").foregroundStyle(.secondary)
                            Text(job.outputDirectory.path.replacingOccurrences(of: ExecutableLocator.realHome, with: "~"))
                                .font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                            Button("Change…", action: chooseOutput).disabled(job.isRunning)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(maxHeight: job.log.isEmpty ? .infinity : 220)

            if !job.log.isEmpty {
                Divider()
                LogView(lines: job.log, title: "Build log")
                    .frame(minHeight: 220)
            }

            Divider()
            HStack {
                if case .failed(let message) = job.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).lineLimit(2)
                }
                Spacer()
                if job.isRunning {
                    Button("Cancel", role: .cancel) { job.cancel() }
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                if case .finished(let url?) = job.phase {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(job.phase == .ready ? "Build Package" : "Build Again") { job.start() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(job.isRunning)
                }
            }
            .padding(16)
        }
        .frame(width: 640, height: job.log.isEmpty ? 480 : 640)
        .interactiveDismissDisabled(job.isRunning)
    }

    @ViewBuilder
    private var phaseBadge: some View {
        switch job.phase {
        case .ready: EmptyView()
        case .running(let step):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(step).font(.callout).foregroundStyle(.secondary) }
        case .finished: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Label("Failed", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var reviewFiles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Review files", systemImage: "exclamationmark.shield").font(.headline)
            Text("Unchecked files stay on this Mac.").font(.caption).foregroundStyle(.secondary)
            ForEach($job.flagged) { $file in
                Toggle(isOn: Binding(get: { !file.excluded }, set: { file.excluded = !$0 })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        Text(file.reason).font(.caption)
                            .foregroundStyle(file.excluded ? Color.secondary : Color(nsColor: .systemOrange))
                    }
                }
                .disabled(job.isRunning)
            }
        }
        .padding(10)
        .background(Color(nsColor: .systemOrange).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func section(_ title: String, _ items: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = job.outputDirectory
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let url = panel.url { job.outputDirectory = url }
    }
}
