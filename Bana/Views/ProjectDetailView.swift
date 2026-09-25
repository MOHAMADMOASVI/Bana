import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    let project: Project
    @ObservedObject var runtime: ProjectRuntime

    @State private var portText = ""
    @State private var commandText = ""
    @State private var showSettings = false
    @State private var hostingJob: HostingJob?
    @State private var showEnv = false
    @State private var showDatabase = false

    var body: some View {
        let type = store.type(of: project)
        VStack(spacing: 14) {
            header(type)
            HStack(alignment: .top, spacing: 14) {
                networkCard
                if showSettings { settingsCard(type) }
            }
            LogView(lines: runtime.log, onClear: runtime.clearLog)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
        }
        .padding(18)
        .navigationTitle(project.name)
        .onAppear(perform: loadSettings)
        .sheet(item: $hostingJob) { HostingSheet(job: $0).localizedUI() }
        .sheet(isPresented: $showDatabase) { DatabaseSheet(project: project).localizedUI() }
        .sheet(isPresented: $showEnv) { LocalEnvSheet(project: project, isRunning: runtime.status.isActive).localizedUI() }
    }

    // MARK: Header

    private func header(_ type: ProjectType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                TypeIcon(type: type, size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(project.name).font(.title2.weight(.bold)).lineLimit(1)
                        StatusBadge(status: runtime.status)
                    }
                    Text("\(type.displayName) · \(project.displayPath)")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 12)
                primaryButton
            }

            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(.tertiary)
                Text(runtime.commandLine.isEmpty ? project.url.path : runtime.commandLine)
                    .font(runtime.commandLine.isEmpty ? .callout : .callout.monospaced()) // paths may be Persian
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .ltr()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            if case .failed(let message) = runtime.status {
                Label(message.rtl, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red).lineLimit(3)
            }

            HStack(spacing: 8) {
                Button { store.openInBrowser(project) } label: {
                    Label(tr("باز کردن در مرورگر", "Open in Browser"), systemImage: "safari")
                }
                .disabled(runtime.status != .running || runtime.port == nil)
                Button { hostingJob = HostingJob(project: project, type: type) } label: {
                    Label(tr("آماده‌سازی هاست", "Prepare for Hosting"), systemImage: "shippingbox.and.arrow.backward")
                }
                .help(tr("ساخت فایل zip آمادهٔ آپلود روی هاست", "Build an upload-ready zip for shared hosting"))
                Button { showDatabase = true } label: {
                    Label(tr("دیتابیس", "Database"), systemImage: "cylinder.split.1x2")
                }
                .help(tr("جدول‌ها، خروجی و وارد کردن SQL", "Tables, SQL export and import"))
                Button { showEnv = true } label: {
                    Label(".env", systemImage: "key.horizontal")
                }
                .help(tr("ویرایش فایل‌های \(lrm(".env")) پروژه", "Edit the project's .env files"))
                Button { NSWorkspace.shared.activateFileViewerSelecting([project.url]) } label: {
                    Label("Finder", systemImage: "folder")
                }
                .help(tr("نمایش در Finder", "Reveal in Finder"))
                Spacer()
                Toggle(isOn: $showSettings.animation(.easeInOut(duration: 0.2))) {
                    Label(tr("تنظیمات پروژه", "Project Settings"), systemImage: "slider.horizontal.3")
                }
                .toggleStyle(.button)
                .help(tr("پورت، نوع و دستور اجرا", "Port, type and command"))
            }
            .controlSize(.regular)
        }
        .card(padding: 16)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if runtime.status.isActive {
            Button { store.stop(project) } label: {
                Label(tr("توقف", "Stop"), systemImage: "stop.fill").frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(runtime.status == .stopping)
            .keyboardShortcut(".", modifiers: .command)
        } else {
            Button { store.start(project) } label: {
                Label(tr("اجرا", "Start"), systemImage: "play.fill").frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: Network

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("دسترسی", "Access"), systemImage: "network").font(.headline)
            if let local = store.url(for: project), runtime.status.isActive {
                let lan = store.url(for: project, lan: true)
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        linkRow(tr("همین مک", "This Mac"), "laptopcomputer", local)
                        if let lan, store.lanIP != nil {
                            linkRow(tr("شبکهٔ محلی", "Local network"), "wifi", lan)
                        } else {
                            Label(tr("به شبکه وصل نیستید — فقط همین مک به سرور دسترسی دارد.", "No network connection — only this Mac can reach the server."),
                                  systemImage: "wifi.slash")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let lan, store.lanIP != nil, let qr = QRCodeGenerator.image(for: lan.absoluteString, pointSize: 112) {
                        VStack(spacing: 6) {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 112, height: 112)
                                .padding(7)
                                .background(.white, in: RoundedRectangle(cornerRadius: 10)) // scanners need dark-on-light
                                .help(lan.absoluteString)
                            Text(tr("اسکن با گوشی", "Scan with a phone")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if runtime.status.isActive {
                Text(tr("بدون پورت منتشرشده در حال اجراست.", "Running without a published port.")).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode").font(.title2).foregroundStyle(.tertiary)
                    Text(tr("سرور را اجرا کنید تا لینک و کد QR ساخته شود.", "Start the server to get a link and QR code."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func linkRow(_ title: String, _ symbol: String, _ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Link(url.absoluteString, destination: url)
                    .font(.body.monospaced())
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(tr("کپی لینک", "Copy link"))
            }
            .ltr()
        }
    }

    // MARK: Project settings

    private func settingsCard(_ type: ProjectType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("تنظیمات پروژه", "Project Settings"), systemImage: "slider.horizontal.3").font(.headline)
            Form {
                Picker(tr("نوع", "Type"), selection: Binding(
                    get: { store.type(of: project) },
                    set: { new in store.updateSettings(for: project) { $0.typeOverride = new == project.detectedType ? nil : new } }
                )) {
                    ForEach(ProjectType.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
                }
                TextField(tr("پورت", "Port"), text: $portText, prompt: Text(tr("خودکار (از \(type.defaultPort))", "Auto (from \(type.defaultPort))")))
                    .onSubmit(savePort)
                TextField(tr("دستور", "Command"), text: $commandText,
                          prompt: Text(CommandBuilder.spec(for: project, type: type, port: 0, customCommand: nil)
                            .displayCommand.replacingOccurrences(of: ":0", with: ":{port}")
                            .replacingOccurrences(of: " 0", with: " {port}")))
                    .font(.body.monospaced())
                    .onSubmit(saveCommand)
            }
            .formStyle(.columns)
            Text(tr("\(lrm("{port}")) با پورت انتخاب‌شده جایگزین می‌شود. دستور مستقیم و بدون shell اجرا می‌شود و از اجرای بعدی اعمال می‌شود.",
                    "{port} is replaced with the chosen port. Runs directly, without a shell. Applies on next start.").rtl)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: portText) { _ in savePort() }
        .onChange(of: commandText) { _ in saveCommand() }
        .frame(width: 380, alignment: .leading)
        .card()
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func loadSettings() {
        let s = store.settings(for: project)
        portText = s.port.map(String.init) ?? ""
        commandText = s.customCommand ?? ""
    }

    private func savePort() {
        let digits = portText.filter(\.isASCII).filter(\.isNumber)
        if digits != portText { portText = digits; return }
        let port = Int(digits).flatMap { (1...65535).contains($0) ? $0 : nil }
        store.updateSettings(for: project) { $0.port = port }
    }

    private func saveCommand() {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateSettings(for: project) { $0.customCommand = trimmed.isEmpty ? nil : trimmed }
    }
}
