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
                    Text("آماده‌سازی برای هاست").font(.title3.weight(.semibold))
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
                        Picker("روش", selection: $job.useProjectScript) {
                            Text("اسکریپت خود پروژه (\(script.pathComponents.suffix(3).joined(separator: "/")))").tag(true)
                            Text("بسته‌ساز بنا").tag(false)
                        }
                        .pickerStyle(.radioGroup)
                        .disabled(job.isRunning)
                    }

                    if job.useProjectScript && job.projectScript != nil {
                        Text("اسکریپت ساخت خود پروژه در پوشهٔ پروژه اجرا می‌شود؛ بنا خروجی آن و فایل zip ساخته‌شده را نشان می‌دهد.")
                            .foregroundStyle(.secondary)
                    } else {
                        section("چیدمان بسته", job.layoutDescription, symbol: "square.stack.3d.up")
                        section("پیش از راه‌اندازی", job.checks, symbol: "checklist")
                        if !job.flagged.isEmpty { reviewFiles }
                        if job.type == .laravel {
                            HStack {
                                Text("آدرس سایت").foregroundStyle(.secondary)
                                TextField("", text: $job.siteAddress, prompt: Text("example.com"))
                                    .textFieldStyle(.roundedBorder)
                                    .ltr()
                                    .frame(maxWidth: 280)
                                    .disabled(job.isRunning)
                                if !job.siteAddress.isEmpty && HostingCopier.normalizedURL(job.siteAddress) == nil {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                        .help("آدرس را با حروف لاتین بنویسید، مثل example.com")
                                }
                            }
                        }
                        if job.hasFrontendBuild && job.type != .python && job.type != .docker {
                            Toggle("اول npm run build اجرا شود", isOn: $job.rebuildFrontend).disabled(job.isRunning)
                        }
                        HStack {
                            Text("محل ذخیره").foregroundStyle(.secondary)
                            Text(job.outputDirectory.path.replacingOccurrences(of: ExecutableLocator.realHome, with: "~"))
                                .font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).ltr()
                            Button("تغییر…", action: chooseOutput).disabled(job.isRunning)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(maxHeight: job.log.isEmpty ? .infinity : 220)

            if !job.log.isEmpty {
                Divider()
                LogView(lines: job.log, title: "گزارش ساخت")
                    .frame(minHeight: 220)
            }

            Divider()
            HStack {
                if case .failed(let message) = job.phase {
                    Label(message.rtl, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).lineLimit(2)
                }
                Spacer()
                if job.isRunning {
                    Button("لغو", role: .cancel) { job.cancel() }
                } else {
                    Button("بستن") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                if case .finished(let url?) = job.phase {
                    Button("نمایش در Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(job.phase == .ready ? "ساخت بسته" : "ساخت دوباره") { job.start() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(job.isRunning)
                }
            }
            .padding(16)
        }
        .frame(width: 640, height: job.log.isEmpty ? 480 : 640)
        .persianUI()
        .interactiveDismissDisabled(job.isRunning)
    }

    @ViewBuilder
    private var phaseBadge: some View {
        switch job.phase {
        case .ready: EmptyView()
        case .running(let step):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(step.rtl).font(.callout).foregroundStyle(.secondary) }
        case .finished: Label("آماده شد", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Label("ناموفق", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var reviewFiles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("بررسی فایل‌ها", systemImage: "exclamationmark.shield").font(.headline)
            Text("فایل‌هایی که تیک ندارند روی همین مک می‌مانند.").font(.caption).foregroundStyle(.secondary)
            ForEach($job.flagged) { $file in
                Toggle(isOn: Binding(get: { !file.excluded }, set: { file.excluded = !$0 })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).ltr()
                        Text(file.reason.rtl).font(.caption)
                            .foregroundStyle(file.excluded ? Color.secondary : Color(nsColor: .systemOrange))
                    }
                }
                .disabled(job.isRunning)
            }
        }
        .padding(10)
        .background(Color(nsColor: .systemOrange).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func section(_ title: LocalizedStringKey, _ items: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item.rtl).fixedSize(horizontal: false, vertical: true)
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
        panel.prompt = "ذخیره در اینجا"
        if panel.runModal() == .OK, let url = panel.url { job.outputDirectory = url }
    }
}
