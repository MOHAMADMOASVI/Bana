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
                    Text(tr("آماده‌سازی برای هاست", "Prepare for Hosting")).font(.title3.weight(.semibold))
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
                        Picker(tr("روش", "Method"), selection: $job.useProjectScript) {
                            Text(tr("اسکریپت خود پروژه", "Project script") + " (\(lrm(script.pathComponents.suffix(3).joined(separator: "/"))))").tag(true)
                            Text(tr("بسته‌ساز بنا", "Bana packager")).tag(false)
                        }
                        .pickerStyle(.radioGroup)
                        .disabled(job.isRunning)
                    }

                    if job.useProjectScript && job.projectScript != nil {
                        Text(tr("اسکریپت ساخت خود پروژه در پوشهٔ پروژه اجرا می‌شود؛ بنا خروجی آن و فایل zip ساخته‌شده را نشان می‌دهد.", "The project's own build script runs in the project folder; Bana shows its output and the zip it produces."))
                            .foregroundStyle(.secondary)
                    } else {
                        section(tr("چیدمان بسته", "Package layout"), job.layoutDescription, symbol: "square.stack.3d.up")
                        section(tr("پیش از راه‌اندازی", "Before going live"), job.checks, symbol: "checklist")
                        if !job.flagged.isEmpty { reviewFiles }
                        if job.type == .laravel {
                            HStack {
                                Text(tr("آدرس سایت", "Site address")).foregroundStyle(.secondary)
                                TextField("", text: $job.siteAddress, prompt: Text("example.com"))
                                    .textFieldStyle(.roundedBorder)
                                    .ltr()
                                    .frame(maxWidth: 280)
                                    .disabled(job.isRunning)
                                if !job.siteAddress.isEmpty && HostingCopier.normalizedURL(job.siteAddress) == nil {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                        .help(tr("آدرس را با حروف لاتین بنویسید، مثل example.com", "Use a Latin (punycode) address like example.com"))
                                }
                            }
                        }
                        if job.hasFrontendBuild && job.type != .python && job.type != .docker {
                            Toggle(tr("اول npm run build اجرا شود", "Run npm run build first"), isOn: $job.rebuildFrontend).disabled(job.isRunning)
                        }
                        HStack {
                            Text(tr("محل ذخیره", "Save to")).foregroundStyle(.secondary)
                            Text(job.outputDirectory.path.replacingOccurrences(of: ExecutableLocator.realHome, with: "~"))
                                .font(.callout).lineLimit(1).truncationMode(.middle).ltr()
                            Button(tr("تغییر…", "Change…"), action: chooseOutput).disabled(job.isRunning)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(maxHeight: job.log.isEmpty ? .infinity : 220)

            if !job.log.isEmpty {
                Divider()
                LogView(lines: job.log, title: tr("گزارش ساخت", "Build log"))
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
                    Button(tr("لغو", "Cancel"), role: .cancel) { job.cancel() }
                } else {
                    Button(tr("بستن", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                }
                if case .finished(let url?) = job.phase {
                    Button(tr("نمایش در Finder", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(job.phase == .ready ? tr("ساخت بسته", "Build Package") : tr("ساخت دوباره", "Build Again")) { job.start() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(job.isRunning)
                }
            }
            .padding(16)
        }
        .frame(width: 640, height: job.log.isEmpty ? 500 : 660)
        .interactiveDismissDisabled(job.isRunning)
    }

    @ViewBuilder
    private var phaseBadge: some View {
        switch job.phase {
        case .ready: EmptyView()
        case .running(let step):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(step.rtl).font(.callout).foregroundStyle(.secondary) }
        case .finished: Label(tr("آماده شد", "Ready"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Label(tr("ناموفق", "Failed"), systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var reviewFiles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tr("بررسی فایل‌ها", "Review files"), systemImage: "exclamationmark.shield").font(.headline)
            Text(tr("فایل‌هایی که تیک ندارند روی همین مک می‌مانند.", "Unchecked files stay on this Mac.")).font(.caption).foregroundStyle(.secondary)
            ForEach($job.flagged) { $file in
                Toggle(isOn: Binding(get: { !file.excluded }, set: { file.excluded = !$0 })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.path).font(.callout).lineLimit(1).truncationMode(.middle).ltr()
                        Text(file.reason.rtl).font(.caption)
                            .foregroundStyle(file.excluded ? Color.secondary : Color(nsColor: .systemOrange))
                    }
                }
                .disabled(job.isRunning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .systemOrange).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func section(_ title: String, _ items: [String], symbol: String) -> some View {
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
        panel.prompt = tr("ذخیره در اینجا", "Save Here")
        if panel.runModal() == .OK, let url = panel.url { job.outputDirectory = url }
    }
}
