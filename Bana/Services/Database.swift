import Foundation

/// Where a project's database lives. Read from .env (Laravel style) or entered by hand.
struct DBConfig: Codable, Equatable {
    enum Driver: String, Codable, CaseIterable, Identifiable {
        case mysql, sqlite
        var id: String { rawValue }
        var title: String { self == .mysql ? "MySQL / MariaDB" : "SQLite" }
    }

    var driver: Driver = .mysql
    var host = "127.0.0.1"
    var port = 3306
    var database = ""
    var username = "root"
    var password = ""
    /// SQLite file (absolute).
    var path = ""

    var displayName: String { driver == .sqlite ? (path as NSString).lastPathComponent : database }
    var endpoint: String { driver == .sqlite ? path : "\(host):\(port)" }
    var isComplete: Bool { driver == .sqlite ? !path.isEmpty : !database.isEmpty && !host.isEmpty }

    /// Laravel-style DB_* keys from the project's .env.
    static func fromEnv(in project: URL) -> DBConfig? {
        guard let text = try? String(contentsOf: project.appendingPathComponent(".env"), encoding: .utf8) else { return nil }
        let doc = EnvDocument(text: text)
        func v(_ key: String) -> String? {
            guard var s = doc.value(key)?.trimmingCharacters(in: .whitespaces) else { return nil }
            if s.count >= 2, let f = s.first, f == s.last, f == "\"" || f == "'" { s = String(s.dropFirst().dropLast()) }
            return s
        }
        guard let connection = v("DB_CONNECTION")?.lowercased() else { return nil }
        var c = DBConfig()
        switch connection {
        case "sqlite":
            c.driver = .sqlite
            let db = v("DB_DATABASE") ?? ""
            c.path = db.isEmpty ? project.appendingPathComponent("database/database.sqlite").path
                : (db.hasPrefix("/") ? db : project.appendingPathComponent(db).path)
        case "mysql", "mariadb":
            c.driver = .mysql
            c.host = v("DB_HOST") ?? "127.0.0.1"
            c.port = Int(v("DB_PORT") ?? "") ?? 3306
            c.database = v("DB_DATABASE") ?? ""
            c.username = v("DB_USERNAME") ?? "root"
            c.password = v("DB_PASSWORD") ?? ""
        default:
            return nil // pgsql etc. not supported
        }
        return c
    }
}

/// Hand-entered connections (for projects without a Laravel .env), owner-only JSON per project.
enum DBConnectionStore {
    static func url(for project: Project) -> URL {
        HostingEnvStore.url(for: project).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("db", isDirectory: true)
            .appendingPathComponent(HostingEnvStore.url(for: project).deletingPathExtension().lastPathComponent + ".json")
    }

    static func load(for project: Project) -> DBConfig? {
        guard let data = try? Data(contentsOf: url(for: project)) else { return nil }
        return try? JSONDecoder().decode(DBConfig.self, from: data)
    }

    static func save(_ config: DBConfig, for project: Project) throws {
        let file = url(for: project)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try EnvFiles.write(String(decoding: try JSONEncoder().encode(config), as: UTF8.self), to: file)
    }

    static func delete(for project: Project) { try? FileManager.default.removeItem(at: url(for: project)) }
}

struct TableInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let rows: Int
    let bytes: Int64
}

struct DBError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Runs a tool and collects its output; stdin/stdout can be files or pipes.
enum CommandRunner {
    struct Output { let status: Int32; let stdout: String; let stderr: String }

    static func run(_ exe: URL, _ args: [String], stdin: Any? = nil, stdout: Any? = nil,
                    onStart: ((Process) -> Void)? = nil) async throws -> Output {
        let process = Process()
        process.executableURL = exe
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env
        process.standardInput = stdin ?? FileHandle.nullDevice
        let outPipe = stdout == nil ? Pipe() : nil
        process.standardOutput = stdout ?? outPipe
        let errPipe = Pipe()
        process.standardError = errPipe

        final class Buffer: @unchecked Sendable { var data = Data(); let lock = NSLock()
            func add(_ d: Data) { lock.lock(); data.append(d); lock.unlock() } }
        let out = Buffer(), err = Buffer()
        let group = DispatchGroup()
        for (pipe, buffer) in [(outPipe, out), (errPipe, err)] {
            guard let pipe else { continue }
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; group.leave() } else { buffer.add(d) }
            }
        }
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        try process.run()
        onStart?(process)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in group.notify(queue: .global()) { c.resume() } }
        return Output(status: process.terminationStatus,
                      stdout: String(decoding: out.data, as: UTF8.self),
                      stderr: String(decoding: err.data, as: UTF8.self))
    }
}

/// mysql / mysqldump / sqlite3 operations for one database.
final class DatabaseClient: @unchecked Sendable {
    let config: DBConfig
    private var running: [Process] = []
    private let lock = NSLock()

    init(config: DBConfig) { self.config = config }

    /// MAMP, Homebrew, XAMPP, DBngin and the official installer — apps from Finder don't have these on PATH.
    static var searchPath: [String] {
        let home = ExecutableLocator.realHome
        var dirs = ["/opt/homebrew/bin", "/opt/homebrew/opt/mysql-client/bin", "/opt/homebrew/opt/mariadb/bin",
                    "/usr/local/bin", "/usr/local/opt/mysql-client/bin", "/usr/local/mysql/bin",
                    "/Applications/MAMP/Library/bin/mysql80/bin", "/Applications/MAMP/Library/bin/mysql57/bin",
                    "/Applications/MAMP/Library/bin", "/Applications/XAMPP/xamppfiles/bin",
                    "\(home)/Library/Application Support/Herd/bin"]
        for base in ["/Users/Shared/DBngin/mysql", "/Users/Shared/DBngin/mariadb"] {
            for v in ((try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []).sorted().reversed() { dirs.append("\(base)/\(v)/bin") }
        }
        return dirs + ["/usr/bin", "/bin"]
    }

    static func tool(_ names: [String]) -> URL? {
        for name in names { if let url = ExecutableLocator.find(name, in: searchPath) { return url } }
        return nil
    }

    func cancel() {
        lock.lock(); let procs = running; lock.unlock()
        procs.forEach { if $0.isRunning { $0.terminate() } }
    }

    private func track(_ p: Process) { lock.lock(); running.append(p); lock.unlock() }

    // MARK: MySQL plumbing

    /// Credentials go in a temporary owner-only option file, never on the command line (visible in `ps`).
    private func withOptionFile<T>(_ body: (String) async throws -> T) async throws -> T {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        // "localhost" makes the client look for a socket in the wrong place (e.g. MAMP); use TCP.
        let host = config.host == "localhost" ? "127.0.0.1" : config.host
        let text = "[client]\nhost=\(q(host))\nport=\(config.port)\nuser=\(q(config.username))\npassword=\(q(config.password))\nprotocol=TCP\ndefault-character-set=utf8mb4\n"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bana-\(UUID().uuidString).cnf")
        FileManager.default.createFile(atPath: file.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: file) }
        return try await body("--defaults-extra-file=\(file.path)")
    }

    private func mysql() throws -> URL {
        guard let exe = Self.tool(["mysql", "mariadb"]) else { throw DBError(tr("ابزار mysql پیدا نشد (MAMP یا brew install mysql-client).", "mysql client not found (MAMP or brew install mysql-client).")) }
        return exe
    }

    private func query(_ sql: String, database: String? = nil) async throws -> [[String]] {
        let exe = try mysql()
        return try await withOptionFile { opt in
            let out = try await CommandRunner.run(exe, [opt, "-N", "-B", "-e", sql] + [database ?? config.database].filter { !$0.isEmpty }, onStart: track)
            if out.status != 0 { throw DBError(Self.clean(out.stderr)) }
            return out.stdout.split(separator: "\n", omittingEmptySubsequences: true).map { $0.components(separatedBy: "\t") }
        }
    }

    private func sqlite() throws -> URL {
        guard let exe = Self.tool(["sqlite3"]) else { throw DBError("sqlite3 not found") }
        return exe
    }

    static func clean(_ stderr: String) -> String {
        stderr.split(separator: "\n").filter { !$0.contains("Using a password on the command line") && !$0.contains("[Warning]") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Read

    func serverVersion() async throws -> String {
        switch config.driver {
        case .mysql: return try await query("SELECT VERSION()", database: "").first?.first ?? "?"
        case .sqlite:
            guard FileManager.default.fileExists(atPath: config.path) else { throw DBError(tr("فایل دیتابیس پیدا نشد.", "Database file not found.")) }
            let out = try await CommandRunner.run(try sqlite(), ["-version"])
            return "SQLite " + (out.stdout.split(separator: " ").first.map(String.init) ?? "")
        }
    }

    func tables() async throws -> [TableInfo] {
        switch config.driver {
        case .mysql:
            let rows = try await query("""
                SELECT TABLE_NAME, IFNULL(TABLE_ROWS,0), IFNULL(DATA_LENGTH,0)+IFNULL(INDEX_LENGTH,0)
                FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME
                """)
            return rows.compactMap { r in r.count >= 3 ? TableInfo(name: r[0], rows: Int(r[1]) ?? 0, bytes: Int64(r[2]) ?? 0) : nil }
        case .sqlite:
            let exe = try sqlite()
            let names = try await CommandRunner.run(exe, [config.path, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"])
            if names.status != 0 { throw DBError(names.stderr) }
            var result: [TableInfo] = []
            for name in names.stdout.split(separator: "\n").map(String.init) {
                let count = try await CommandRunner.run(exe, [config.path, "SELECT COUNT(*) FROM \"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""])
                result.append(TableInfo(name: name, rows: Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0, bytes: 0))
            }
            return result
        }
    }

    // MARK: Export

    struct ExportOptions: Equatable {
        var includeData = true
        /// phpMyAdmin on shared hosting: no DEFINER (needs SUPER), no tablespaces, no DROP TABLE.
        var forHosting = false
        var gzip = false
    }

    /// Writes a dump to `destination` (".gz" is added when gzip is on). Returns the final file.
    func export(to destination: URL, options: ExportOptions, log: @escaping (String) -> Void) async throws -> URL {
        let sqlFile = destination.pathExtension == "gz" ? destination.deletingPathExtension() : destination
        FileManager.default.createFile(atPath: sqlFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: sqlFile)
        var ok = false
        defer { if !ok { try? FileManager.default.removeItem(at: sqlFile) } }

        switch config.driver {
        case .mysql:
            guard let dump = Self.tool(["mysqldump", "mariadb-dump"]) else {
                throw DBError(tr("ابزار mysqldump پیدا نشد.", "mysqldump not found."))
            }
            let isMaria = (try? await CommandRunner.run(dump, ["--version"]).stdout.contains("MariaDB")) ?? false
            var args = ["--single-transaction", "--routines", "--triggers", "--events", "--hex-blob",
                        "--no-tablespaces", "--default-character-set=utf8mb4"]
            if !isMaria { args.append("--set-gtid-purged=OFF") }
            if !options.includeData { args.append("--no-data") }
            if options.forHosting { args.append("--skip-add-drop-table") }
            args.append(config.database)
            log("$ \(dump.lastPathComponent) \(args.joined(separator: " "))")
            let out = try await withOptionFile { opt in
                try await CommandRunner.run(dump, [opt] + args, stdout: handle, onStart: track)
            }
            try handle.close()
            if out.status != 0 { throw DBError(Self.clean(out.stderr)) }
            if options.forHosting {
                let n = try SQLFilter.stripDefiners(in: sqlFile)
                if n > 0 { log(tr("\(n) مورد DEFINER حذف شد (هاست اشتراکی اجازه‌اش را نمی‌دهد).", "Removed \(n) DEFINER clause(s) (not allowed on shared hosting).")) }
            }
        case .sqlite:
            let args = [config.path, options.includeData ? ".dump" : ".schema"]
            log("$ sqlite3 \(args.joined(separator: " "))")
            let out = try await CommandRunner.run(try sqlite(), args, stdout: handle, onStart: track)
            try handle.close()
            if out.status != 0 { throw DBError(out.stderr) }
        }

        var final = sqlFile
        if options.gzip {
            let out = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/gzip"), ["-f", "-9", sqlFile.path])
            if out.status != 0 { throw DBError(out.stderr) }
            final = sqlFile.appendingPathExtension("gz")
        }
        ok = true
        let size = (try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        log(tr("✓ خروجی: \(final.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))",
               "✓ Exported \(final.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"))
        return final
    }

    // MARK: Import

    func importFile(_ file: URL, log: @escaping (String) -> Void) async throws {
        let gz = file.pathExtension.lowercased() == "gz"
        var gunzip: Process?
        let input: Any
        if gz {
            let pipe = Pipe()
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
            p.arguments = ["-c", file.path]
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            try p.run()
            track(p)
            gunzip = p
            input = pipe.fileHandleForReading
        } else {
            input = try FileHandle(forReadingFrom: file)
        }

        let out: CommandRunner.Output
        switch config.driver {
        case .mysql:
            let exe = try mysql()
            log("$ \(exe.lastPathComponent) \(config.database) < \(file.lastPathComponent)")
            out = try await withOptionFile { opt in
                try await CommandRunner.run(exe, [opt, config.database], stdin: input, onStart: track)
            }
        case .sqlite:
            log("$ sqlite3 \(config.path) < \(file.lastPathComponent)")
            out = try await CommandRunner.run(try sqlite(), [config.path], stdin: input, onStart: track)
        }
        gunzip?.waitUntilExit()
        if out.status != 0 { throw DBError(Self.clean(out.stderr)) }
        if let g = gunzip, g.terminationStatus != 0 { throw DBError(tr("فایل gzip خراب است.", "The gzip file is damaged.")) }
        log(tr("✓ وارد شد: \(file.lastPathComponent)", "✓ Imported \(file.lastPathComponent)"))
    }

    // MARK: Test helpers (temporary databases on the same server)

    func createDatabase(_ name: String) async throws {
        _ = try await query("CREATE DATABASE `\(name)` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", database: "")
    }

    func dropDatabase(_ name: String) async throws {
        precondition(name.hasPrefix("bana_tmp_"), "only temporary databases are dropped")
        _ = try await query("DROP DATABASE IF EXISTS `\(name)`", database: "")
    }
}

enum SQLFilter {
    private static let definer = try! NSRegularExpression(pattern: #"\s*DEFINER\s*=\s*(`[^`]*`|'[^']*'|[^\s@]+)@(`[^`]*`|'[^']*'|[^\s*]+)"#)

    /// Removes DEFINER=user@host clauses in place, streaming (dumps can be large). Returns how many were removed.
    @discardableResult
    static func stripDefiners(in file: URL) throws -> Int {
        let tmp = file.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let reader = try FileHandle(forReadingFrom: file)
        let writer = try FileHandle(forWritingTo: tmp)
        var carry = Data(), removed = 0

        func process(_ chunk: Data) {
            guard let text = String(data: chunk, encoding: .utf8) else { writer.write(chunk); return }
            guard text.contains("DEFINER") else { writer.write(chunk); return }
            let range = NSRange(text.startIndex..., in: text)
            removed += definer.numberOfMatches(in: text, range: range)
            writer.write(Data(definer.stringByReplacingMatches(in: text, range: range, withTemplate: "").utf8))
        }

        while true {
            let data = reader.readData(ofLength: 1 << 20)
            if data.isEmpty { break }
            carry.append(data)
            // Only process whole lines so a clause is never split across chunks.
            if let nl = carry.lastIndex(of: 0x0A) {
                process(carry[carry.startIndex...nl])
                carry = Data(carry[carry.index(after: nl)...])
            }
        }
        if !carry.isEmpty { process(carry) }
        try reader.close(); try writer.close()
        _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
        return removed
    }
}
