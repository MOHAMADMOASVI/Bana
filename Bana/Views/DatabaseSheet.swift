import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DatabaseModel: ObservableObject {
    enum Source { case env, manual, none }

    let project: Project
    @Published private(set) var config: DBConfig?
    @Published private(set) var source: Source = .none
    @Published private(set) var version: String?
    @Published private(set) var tables: [TableInfo] = []
    @Published private(set) var error: String?
    @Published private(set) var busy: String?
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var lastFile: URL?
    private var client: DatabaseClient?
    private var nextID = 0

    init(project: Project) {
        self.project = project
        loadConfig()
    }

    static var backupFolder: URL {
        URL(fileURLWithPath: ExecutableLocator.realHome + "/Documents/Bana/Database Backups", isDirectory: true)
    }

    var totalRows: Int { tables.reduce(0) { $0 + $1.rows } }
    var totalBytes: Int64 { tables.reduce(0) { $0 + $1.bytes } }

    func loadConfig() {
        if let manual = DBConnectionStore.load(for: project) { config = manual; source = .manual }
        else if let env = DBConfig.fromEnv(in: project.url) { config = env; source = .env }
        else { config = nil; source = .none }
        client = config.map(DatabaseClient.init)
    }

    func saveManual(_ c: DBConfig?) {
        if let c { try? DBConnectionStore.save(c, for: project) } else { DBConnectionStore.delete(for: project) }
        loadConfig()
        Task { await refresh() }
    }

    func refresh() async {
        guard let client else { return }
        error = nil
        busy = tr("اتصال…", "Connecting…")
        defer { busy = nil }
        do {
            version = try await client.serverVersion()
            tables = try await client.tables()
        } catch {
            version = nil
            tables = []
            self.error = error.localizedDescription
        }
    }

    func export(to url: URL, options: DatabaseClient.ExportOptions) async {
        guard let client else { return }
        busy = tr("در حال گرفتن خروجی…", "Exporting…")
        defer { busy = nil }
        do {
            lastFile = try await client.export(to: url, options: options) { [weak self] in self?.append($0) }
        } catch {
            append("✗ " + error.localizedDescription)
            self.error = error.localizedDescription
        }
    }

    /// Optional safety backup first, then the import. Tables are re-read afterwards.
    func importFile(_ url: URL, backupFirst: Bool) async {
        guard let client, let config else { return }
        busy = tr("در حال وارد کردن…", "Importing…")
        defer { busy = nil }
        do {
            if backupFirst {
                try FileManager.default.createDirectory(at: Self.backupFolder, withIntermediateDirectories: true)
                let name = "\(config.displayName)-before-import-\(Self.stamp()).sql.gz"
                let backup = try await client.export(to: Self.backupFolder.appendingPathComponent(name),
                                                     options: .init(includeData: true, forHosting: false, gzip: true)) { [weak self] in self?.append($0) }
                append(tr("بکاپ پیش از import: \(backup.path)", "Backup before import: \(backup.path)"))
                lastFile = backup
            }
            try await client.importFile(url) { [weak self] in self?.append($0) }
        } catch {
            append("✗ " + error.localizedDescription)
            self.error = error.localizedDescription
        }
        await refresh()
    }

    func cancel() { client?.cancel() }

    func suggestedName(options: DatabaseClient.ExportOptions) -> String {
        let base = config?.displayName.replacingOccurrences(of: ".sqlite", with: "") ?? "database"
        let kind = options.forHosting ? "-host" : (options.includeData ? "" : "-schema")
        return "\(base)\(kind)-\(Self.stamp()).sql" + (options.gzip ? ".gz" : "")
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    private func append(_ text: String) {
        log.append(LogLine(id: nextID, text: text, stream: .system))
        nextID += 1
    }
}

struct DatabaseSheet: View {
    @StateObject private var model: DatabaseModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportOptions = DatabaseClient.ExportOptions()
    @State private var showExport = false
    @State private var pendingImport: URL?
    @State private var editingConnection = false

    init(project: Project) { _model = StateObject(wrappedValue: DatabaseModel(project: project)) }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(16)
            Divider()
            if model.config == nil {
                noConnection
            } else {
                content
            }
            Divider()
            footer.padding(14)
        }
        .frame(width: 720, height: 620)
        .task { await model.refresh() }
        .sheet(isPresented: $showExport) { exportSheet.localizedUI() }
        .sheet(item: $pendingImport) { url in
            ImportConfirmSheet(model: model, file: url).localizedUI()
        }
        .sheet(isPresented: $editingConnection) {
            ConnectionEditor(initial: model.config ?? DBConfig(), canReset: model.source == .manual) { model.saveManual($0) }
                .localizedUI()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cylinder.split.1x2.fill")
                .font(.title2).foregroundStyle(.orange)
                .frame(width: 44, height: 44)
                .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.config?.displayName ?? tr("دیتابیس", "Database")).font(.title3.weight(.semibold))
                    if model.version != nil {
                        connectedBadge
                    }
                }
                if let c = model.config {
                    Text("\(c.driver.title) · \(c.endpoint)\(model.version.map { " · \($0)" } ?? "")")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).ltr()
                }
                Text(sourceLabel).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button { editingConnection = true } label: { Label(tr("اتصال…", "Connection…"), systemImage: "network") }
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .help(tr("تازه‌سازی", "Refresh"))
                .disabled(model.config == nil || model.busy != nil)
        }
    }

    private var connectedBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text(tr("وصل", "Connected"))
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(.green)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.green.opacity(0.13), in: Capsule())
    }

    private var sourceLabel: String {
        switch model.source {
        case .env: tr("مشخصات از فایل \(lrm(".env")) پروژه", "Connection from the project's .env").rtl
        case .manual: tr("مشخصات دستی (فقط روی همین مک ذخیره شده)", "Manual connection (saved on this Mac only)")
        case .none: ""
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { showExport = true } label: { Label(tr("خروجی گرفتن…", "Export…"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent)
                Button { chooseImport() } label: { Label(tr("وارد کردن…", "Import…"), systemImage: "square.and.arrow.down") }
                Spacer()
                if !model.tables.isEmpty {
                    Text(tr("\(num(model.tables.count)) جدول · حدود \(num(model.totalRows)) ردیف · \(size(model.totalBytes))",
                            "\(model.tables.count) tables · ~\(model.totalRows) rows · \(size(model.totalBytes))"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .disabled(model.busy != nil)
            .padding(.horizontal, 16).padding(.vertical, 10)

            if let error = model.error {
                Label(error.rtl, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout).lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }

            Table(model.tables) {
                TableColumn(tr("جدول", "Table")) { Text($0.name).font(.body.monospaced()) }
                TableColumn(tr("ردیف‌ها", "Rows")) { t in
                    Text((model.config?.driver == .mysql ? "≈ " : "") + num(t.rows)).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(110)
                TableColumn(tr("حجم", "Size")) { t in
                    Text(t.bytes > 0 ? size(t.bytes) : "—").monospacedDigit().foregroundStyle(.secondary)
                }
                .width(90)
            }
            .ltr()
            .overlay {
                if model.tables.isEmpty && model.error == nil && model.busy == nil {
                    Text(tr("این دیتابیس جدولی ندارد.", "This database has no tables.")).foregroundStyle(.secondary)
                }
            }

            if !model.log.isEmpty {
                Divider()
                LogView(lines: model.log, title: tr("گزارش", "Log")).frame(height: 150)
            }
        }
    }

    private var noConnection: some View {
        VStack(spacing: 12) {
            Image(systemName: "cylinder.split.1x2").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(tr("مشخصات دیتابیس این پروژه پیدا نشد.", "No database settings found for this project.")).font(.headline)
            Text(tr("در \(lrm(".env")) پروژه DB_CONNECTION نیست؛ مشخصات را دستی وارد کنید.", "The project's .env has no DB_CONNECTION; enter the connection by hand.").rtl)
                .foregroundStyle(.secondary)
            Button(tr("وارد کردن مشخصات…", "Enter Connection…")) { editingConnection = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if let busy = model.busy {
                ProgressView().controlSize(.small)
                Text(busy).foregroundStyle(.secondary)
                Button(tr("لغو", "Cancel")) { model.cancel() }.controlSize(.small)
            } else if let file = model.lastFile {
                Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: {
                    Label(tr("نمایش آخرین فایل در Finder", "Show last file in Finder"), systemImage: "folder")
                }
            }
            Spacer()
            Button(tr("بستن", "Close")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy != nil)
        }
    }

    // MARK: Export

    private var exportSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("خروجی گرفتن از \(model.config?.displayName ?? "")", "Export \(model.config?.displayName ?? "")"), systemImage: "square.and.arrow.up")
                .font(.title3.weight(.semibold))
            Toggle(tr("همراه با داده‌ها", "Include data"), isOn: $exportOptions.includeData)
            Text(tr("خاموش: فقط ساختار جدول‌ها.", "Off: table structure only.")).font(.caption).foregroundStyle(.secondary)
            if model.config?.driver == .mysql {
                Toggle(tr("مناسب هاست (phpMyAdmin)", "For shared hosting (phpMyAdmin)"), isOn: $exportOptions.forHosting)
                Text(tr("DEFINER و DROP TABLE حذف می‌شوند؛ import روی دیتابیسی که جدول دارد به‌جای پاک کردن، خطا می‌دهد.",
                        "Removes DEFINER and DROP TABLE; importing over existing tables fails instead of wiping them.").rtl)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Toggle(tr("فشرده (gz)", "Compress (gz)"), isOn: $exportOptions.gzip)
            HStack {
                Spacer()
                Button(tr("لغو", "Cancel")) { showExport = false }.keyboardShortcut(.cancelAction)
                Button(tr("ذخیره…", "Save…")) {
                    showExport = false
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = model.suggestedName(options: exportOptions)
                    panel.directoryURL = HostingJob.defaultOutputDirectory
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        let opts = exportOptions
                        Task { await model.export(to: url, options: opts) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sql") ?? .plainText, .gzip]
        panel.allowsMultipleSelection = false
        panel.message = tr("فایل .sql یا .sql.gz را انتخاب کنید", "Choose a .sql or .sql.gz file")
        if panel.runModal() == .OK, let url = panel.url { pendingImport = url }
    }

    private func size(_ bytes: Int64) -> String { lrm(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
}

/// Import changes data: always offer a backup, and ask for the database name when it already has tables.
struct ImportConfirmSheet: View {
    @ObservedObject var model: DatabaseModel
    let file: URL
    @Environment(\.dismiss) private var dismiss
    @State private var backupFirst = true
    @State private var typedName = ""

    private var dbName: String { model.config?.displayName ?? "" }
    private var needsTyping: Bool { !model.tables.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("وارد کردن به \(dbName)", "Import into \(dbName)"), systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold)).foregroundStyle(.orange)
            Text(tr("فایل «\(file.lastPathComponent)» روی دیتابیس «\(dbName)» اجرا می‌شود و می‌تواند داده‌های فعلی را تغییر دهد یا پاک کند.",
                    "“\(file.lastPathComponent)” will run against “\(dbName)” and can change or delete its current data."))
                .fixedSize(horizontal: false, vertical: true)
            if needsTyping {
                Text(tr("این دیتابیس \(num(model.tables.count)) جدول دارد.", "This database has \(model.tables.count) tables."))
                    .foregroundStyle(.secondary)
            }
            Toggle(tr("اول بکاپ کامل گرفته شود", "Take a full backup first"), isOn: $backupFirst)
            Text(DatabaseModel.backupFolder.path.replacingOccurrences(of: ExecutableLocator.realHome, with: "~"))
                .font(.caption).foregroundStyle(.secondary).ltr()
            if needsTyping {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("برای تأیید، نام دیتابیس را بنویسید:", "To confirm, type the database name:")).font(.callout)
                    TextField(dbName, text: $typedName).textFieldStyle(.roundedBorder).font(.body.monospaced()).ltr()
                }
            }
            HStack {
                Spacer()
                Button(tr("لغو", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("وارد کردن", "Import"), role: .destructive) {
                    let backup = backupFirst
                    dismiss()
                    Task { await model.importFile(file, backupFirst: backup) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(needsTyping && typedName != dbName)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Manual connection for projects without a Laravel .env (or to override it).
struct ConnectionEditor: View {
    @State var config: DBConfig
    let canReset: Bool
    let onSave: (DBConfig?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var portText: String

    init(initial: DBConfig, canReset: Bool, onSave: @escaping (DBConfig?) -> Void) {
        _config = State(initialValue: initial)
        _portText = State(initialValue: String(initial.port))
        self.canReset = canReset
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tr("اتصال دیتابیس", "Database Connection"), systemImage: "network").font(.title3.weight(.semibold))
            Form {
                Picker(tr("نوع", "Type"), selection: $config.driver) {
                    ForEach(DBConfig.Driver.allCases) { Text($0.title).tag($0) }
                }
                if config.driver == .mysql {
                    TextField(tr("میزبان", "Host"), text: $config.host)
                    TextField(tr("پورت", "Port"), text: $portText)
                    TextField(tr("دیتابیس", "Database"), text: $config.database)
                    TextField(tr("کاربر", "User"), text: $config.username)
                    SecureField(tr("رمز", "Password"), text: $config.password)
                } else {
                    HStack {
                        TextField(tr("فایل", "File"), text: $config.path)
                        Button(tr("انتخاب…", "Choose…")) {
                            let panel = NSOpenPanel()
                            if panel.runModal() == .OK, let url = panel.url { config.path = url.path }
                        }
                    }
                }
            }
            .formStyle(.columns)
            .ltr()
            Text(tr("مشخصات دستی بر \(lrm(".env")) پروژه مقدم است و فقط روی همین مک ذخیره می‌شود (دسترسی فقط برای شما).",
                    "A manual connection takes precedence over the project's .env and is saved on this Mac only (owner-only)."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if canReset {
                    Button(tr("برگشت به \(lrm(".env"))", "Use .env Again").rtl) { onSave(nil); dismiss() }
                }
                Spacer()
                Button(tr("لغو", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("ذخیره", "Save")) {
                    config.port = Int(portText.filter(\.isNumber)) ?? 3306
                    onSave(config)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!config.isComplete)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
