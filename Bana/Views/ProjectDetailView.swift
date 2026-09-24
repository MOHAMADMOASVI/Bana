import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    @ObservedObject var runtime: ProjectRuntime

    @State private var portText = ""
    @State private var commandText = ""
    @State private var showSettings = false
    @State private var hostingJob: HostingJob?

    var body: some View {
        let type = store.type(of: project)
        VStack(spacing: 0) {
            header(type)
                .padding(16)
            Divider()
            HStack(alignment: .top, spacing: 16) {
                networkBox
                if showSettings { settingsBox(type) }
            }
            .padding(16)
            LogView(lines: runtime.log, onClear: runtime.clearLog)
        }
        .navigationTitle(project.name)
        .navigationSubtitle(project.relativePath)
        .onAppear(perform: loadSettings)
        .sheet(item: $hostingJob) { HostingSheet(job: $0) }
    }

    // MARK: Header

    private func header(_ type: ProjectType) -> some View {
        HStack(spacing: 12) {
            TypeIcon(type: type, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.name).font(.title2.weight(.semibold)).lineLimit(1)
                    StatusBadge(status: runtime.status)
                }
                Text(runtime.commandLine.isEmpty ? project.url.path : runtime.commandLine)
                    .ltr()
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                if case .failed(let message) = runtime.status {
                    Text(message.rtl).font(.callout).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() }
            } label: {
                Label("تنظیمات", systemImage: "slider.horizontal.3").labelStyle(.iconOnly)
            }
            .help("تنظیمات: پورت و دستور اجرا")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([project.url])
            } label: {
                Label("Finder", systemImage: "folder").labelStyle(.iconOnly)
            }
            .help("نمایش در Finder")
            Button {
                hostingJob = HostingJob(project: project, type: type)
            } label: {
                Label("هاست", systemImage: "shippingbox.and.arrow.backward")
            }
            .help("ساخت فایل zip آمادهٔ آپلود روی هاست")
            Button {
                store.openInBrowser(project)
            } label: {
                Label("باز کردن در مرورگر", systemImage: "safari")
            }
            .disabled(runtime.status != .running || runtime.port == nil)
            if runtime.status.isActive {
                Button(role: .destructive) { store.stop(project) } label: {
                    Label("توقف", systemImage: "stop.fill").frame(minWidth: 56)
                }
                .disabled(runtime.status == .stopping)
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button { store.start(project) } label: {
                    Label("اجرا", systemImage: "play.fill").frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.large)
    }

    // MARK: Network

    private var networkBox: some View {
        GroupBox {
            if let local = store.url(for: project), runtime.status.isActive {
                let lan = store.url(for: project, lan: true)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        linkRow("همین مک", local)
                        if let lan, store.lanIP != nil {
                            linkRow("شبکهٔ محلی", lan)
                            Text("با گوشیِ وصل به همین Wi‑Fi کد را اسکن کنید.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Label("به شبکه وصل نیستید — فقط همین مک به سرور دسترسی دارد.", systemImage: "wifi.slash")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let lan, store.lanIP != nil, let qr = QRCodeGenerator.image(for: lan.absoluteString, pointSize: 120) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 120, height: 120)
                            .padding(6)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8)) // scanners need dark-on-light
                            .help(lan.absoluteString)
                    }
                }
                .padding(6)
            } else if runtime.status.isActive {
                Text("بدون پورت منتشرشده در حال اجراست.").foregroundStyle(.secondary).padding(6)
            } else {
                HStack {
                    Image(systemName: "network").foregroundStyle(.tertiary)
                    Text("سرور را اجرا کنید تا لینک و کد QR ساخته شود.").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(6)
            }
        } label: {
            Label("شبکه", systemImage: "network")
        }
        .frame(maxWidth: .infinity)
    }

    private func linkRow(_ title: LocalizedStringKey, _ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Link(url.absoluteString, destination: url)
                    .ltr()
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("کپی لینک")
            }
        }
    }

    // MARK: Settings

    private func settingsBox(_ type: ProjectType) -> some View {
        GroupBox {
            Form {
                Picker("نوع", selection: Binding(
                    get: { store.type(of: project) },
                    set: { new in store.updateSettings(for: project) { $0.typeOverride = new == project.detectedType ? nil : new } }
                )) {
                    ForEach(ProjectType.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
                }
                TextField("پورت", text: $portText, prompt: Text("خودکار (از \(String(type.defaultPort)))"))
                    .ltr()
                    .onSubmit(savePort)
                TextField("دستور", text: $commandText,
                          prompt: Text(CommandBuilder.spec(for: project, type: type, port: 0, customCommand: nil)
                            .displayCommand.replacingOccurrences(of: ":0", with: ":{port}")
                            .replacingOccurrences(of: " 0", with: " {port}")))
                    .font(.body.monospaced())
                    .ltr()
                    .onSubmit(saveCommand)
                Text("`\(lrm("{port}"))` با پورت انتخاب‌شده جایگزین می‌شود. دستور مستقیم و بدون shell اجرا می‌شود و از اجرای بعدی اعمال می‌شود.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.columns)
            .padding(6)
            .onChange(of: portText) { _ in savePort() }
            .onChange(of: commandText) { _ in saveCommand() }
        } label: {
            Label("تنظیمات", systemImage: "slider.horizontal.3")
        }
        .frame(width: 380)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func loadSettings() {
        let s = store.settings(for: project)
        portText = s.port.map(String.init) ?? ""
        commandText = s.customCommand ?? ""
    }

    private func savePort() {
        let digits = portText.filter(\.isNumber)
        if digits != portText { portText = digits; return }
        let port = Int(digits).flatMap { (1...65535).contains($0) ? $0 : nil }
        store.updateSettings(for: project) { $0.port = port }
    }

    private func saveCommand() {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateSettings(for: project) { $0.customCommand = trimmed.isEmpty ? nil : trimmed }
    }
}
