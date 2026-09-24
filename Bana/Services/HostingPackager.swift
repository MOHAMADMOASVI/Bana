import Foundation

/// Builds an upload-ready zip for shared hosting (cPanel / DirectAdmin, no SSH):
///
///     <app>/          the application, outside the web root   (Laravel, PHP with public/)
///     public_html/    what the domain serves
///     README-HOSTING.txt
///
/// If the project ships its own `deploy/**/build.sh`, that script can be run instead.
@MainActor
final class HostingJob: ObservableObject {
    enum Phase: Equatable {
        case ready
        case running(String)
        case finished(URL?)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var log: [LogLine] = []
    @Published var useProjectScript: Bool
    @Published var rebuildFrontend = true
    /// Becomes APP_URL (Laravel); "example.com" → "https://example.com".
    @Published var siteAddress = ""
    @Published var outputDirectory: URL
    /// Files that look like backups, dumps or secrets; the user decides per file.
    @Published var flagged: [FlaggedFile]

    let project: Project
    let type: ProjectType
    let projectScript: URL?

    private var current: Process?
    private var cancelled = false
    private var nextLineID = 0

    init(project: Project, type: ProjectType) {
        self.project = project
        self.type = type
        projectScript = Self.findProjectScript(in: project.url)
        useProjectScript = projectScript != nil
        outputDirectory = URL(fileURLWithPath: ExecutableLocator.realHome + "/Desktop")
        flagged = HostingCopier.flaggedFiles(in: project.url, type: type)
    }

    /// Zip base name; generic folder names get their parent's name ("fanal-app-pasargad-php").
    var packageName: String {
        let generic: Set<String> = ["php", "laravel", "web", "app", "src", "site", "backend", "frontend", "api", "public", "www"]
        let name = project.name
        let parent = project.url.deletingLastPathComponent().lastPathComponent
        let base = generic.contains(name.lowercased()) && !parent.isEmpty ? "\(parent)-\(name)" : name
        return base.replacingOccurrences(of: " ", with: "-")
    }

    var isRunning: Bool { if case .running = phase { return true }; return false }

    /// Folder name for the app inside the zip; hosts dislike spaces and non-ASCII.
    var appFolderName: String {
        let name = project.name.lowercased()
        let ok = !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return ok ? name : "app"
    }

    /// Split layout: app outside the web root, only public/ served.
    var usesSplitLayout: Bool {
        type == .laravel || (type == .php && FileManager.default.fileExists(atPath: project.url.appendingPathComponent("public/index.php").path))
    }

    var hasFrontendBuild: Bool { CommandBuilder.packageScripts(in: project.url)["build"] != nil }

    /// What the zip will contain, in plain words.
    var layoutDescription: [String] {
        if usesSplitLayout {
            return ["\(lrm("\(appFolderName)/")) — خود برنامه، بیرون از دسترس وب (vendor با \(lrm("--no-dev")) نصب می‌شود)",
                    "\(lrm("public_html/")) — محتوای \(lrm("public/"))؛ index.php به \(lrm("../\(appFolderName)/")) اشاره می‌کند",
                    "در پوشهٔ دامنه (مثلاً \(lrm("domains/example.com/"))) Extract کنید تا \(lrm("public_html/")) روی همان پوشهٔ موجود بنشیند."]
        }
        switch type {
        case .laravel, .php:
            return ["\(lrm("public_html/")) — کل پروژه (خودش ریشهٔ وب است)",
                    "در پوشهٔ دامنه Extract کنید، یا محتوای \(lrm("public_html/")) را آپلود کنید."]
        case .node:
            return ["\(lrm("public_html/")) — خروجی استاتیک ساخت (\(lrm("dist/"))، \(lrm("build/")) یا \(lrm("out/"))) اگر پروژه داشته باشد",
                    "وگرنه \(lrm("\(appFolderName)/")) — پروژه بدون node_modules، برای «Setup Node.js App» هاست."]
        case .python:
            return ["\(lrm("\(appFolderName)/")) — پروژه بدون virtualenv و کش، برای «Setup Python App» هاست."]
        case .docker:
            return ["\(lrm("\(appFolderName)/")) — پروژه بدون \(lrm(".git"))، برای سروری که docker compose اجرا می‌کند."]
        }
    }

    /// Things worth knowing before uploading.
    var checks: [String] {
        var notes = ["فایل \(lrm(".env")) لوکال هیچ‌وقت داخل بسته نمی‌رود."]
        let dir = project.url
        if let data = try? Data(contentsOf: dir.appendingPathComponent("composer.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let php = (json["require"] as? [String: Any])?["php"] as? String { notes.append("به PHP \(php) نیاز دارد — همین نسخه را در پنل هاست انتخاب کنید.") }
            if let platform = ((json["config"] as? [String: Any])?["platform"] as? [String: Any])?["php"] as? String {
                notes.append("composer.json نسخهٔ PHP را روی \(platform) قفل کرده؛ vendor برای همان نسخه ساخته می‌شود.")
            }
        }
        if type == .laravel {
            notes.append("یک \(lrm(".env")) مخصوص هاست از روی \(lrm(".env.example")) ساخته می‌شود، با APP_KEY تازه و APP_DEBUG=false — مشخصات دیتابیس را روی هاست وارد کنید.")
            notes.append("storage/app (فایل‌های آپلودی و بکاپ‌های لوکال) داخل بسته نیست و هاست خالی شروع می‌کند. اگر داده منتقل می‌کنید، جدا آپلودش کنید.")
            notes.append("بدون SSH: جدول‌ها را با import در phpMyAdmin یا یک Cron یک‌باره بسازید.")
        }
        if type == .php && !usesSplitLayout {
            notes.append("همهٔ فایل‌های پوشهٔ پروژه از طریق وب در دسترس می‌شوند — رمزها را بیرون از آن نگه دارید.")
        }
        return notes
    }

    // MARK: Run

    func start() {
        guard !isRunning else { return }
        log.removeAll()
        cancelled = false
        Task {
            do {
                let result = useProjectScript && projectScript != nil ? try await runProjectScript() : try await runBuiltIn()
                phase = .finished(result)
                if let result { append("✓ \(result.path)", .system) }
            } catch {
                phase = cancelled ? .ready : .failed(error.localizedDescription)
                append(cancelled ? "لغو شد." : "✗ \(error.localizedDescription)", .system)
            }
        }
    }

    func cancel() {
        cancelled = true
        if let current { ProcessTree.signal(ProcessTree.descendants(of: current.processIdentifier), SIGTERM); current.terminate() }
    }

    private func runProjectScript() async throws -> URL? {
        guard let script = projectScript else { return nil }
        let started = Date()
        phase = .running("اجرای \(relative(script))")
        if FileManager.default.isExecutableFile(atPath: script.path) {
            try await exec(script.path, [], in: project.url)
        } else {
            try await exec("/bin/bash", [script.path], in: project.url)
        }
        return Self.newestZip(in: project.url, since: started)
    }

    private func runBuiltIn() async throws -> URL {
        let fm = FileManager.default
        let src = project.url
        let stage = fm.temporaryDirectory.appendingPathComponent("bana-hosting-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        let app = appFolderName

        if hasFrontendBuild && rebuildFrontend && type != .python && type != .docker {
            phase = .running("ساخت فایل‌های فرانت‌اند")
            if !fm.fileExists(atPath: src.appendingPathComponent("node_modules").path) {
                let lock = fm.fileExists(atPath: src.appendingPathComponent("package-lock.json").path)
                try await exec("npm", lock ? ["ci"] : ["install"], in: src)
            }
            try await exec("npm", ["run", "build"], in: src)
        }
        try checkCancelled()

        phase = .running("کپی فایل‌ها")
        let reinstallVendor = fm.fileExists(atPath: src.appendingPathComponent("composer.json").path)
        var target: URL
        switch type {
        case .php where !usesSplitLayout:
            target = stage.appendingPathComponent("public_html")
        case .node:
            if let out = staticOutput() {
                target = stage.appendingPathComponent("public_html")
                try fm.createDirectory(at: stage, withIntermediateDirectories: true)
                try fm.copyItem(at: out, to: target)
                append("سایت استاتیک از \(lrm(out.lastPathComponent + "/"))", .system)
                return try await finish(stage: stage)
            }
            target = stage.appendingPathComponent(app)
        default:
            target = stage.appendingPathComponent(app)
        }
        let excluded = Set(flagged.filter(\.excluded).map(\.path))
        let copied = try HostingCopier.copy(from: src, to: target, type: type, skipVendor: reinstallVendor, excluding: excluded)
        append("\(copied) فایل کپی شد (بدون \(lrm(".git"))، node_modules، \(lrm(".env")) لوکال، لاگ‌ها و کش‌ها).", .system)
        for path in excluded.sorted() { append("کنار گذاشته شد: \(path)", .system) }
        try checkCancelled()

        if type == .laravel || (type == .php && usesSplitLayout) {
            HostingCopier.recreateLaravelRuntimeDirs(in: target)
        }

        if reinstallVendor {
            phase = .running("نصب وابستگی‌های PHP (\(lrm("--no-dev")))")
            try await exec("composer", ["install", "--no-dev", "--optimize-autoloader", "--no-interaction", "--prefer-dist", "--no-progress"], in: target)
        }
        try checkCancelled()

        if usesSplitLayout {
            phase = .running("چیدن public_html")
            let publicHTML = stage.appendingPathComponent("public_html")
            try fm.moveItem(at: target.appendingPathComponent("public"), to: publicHTML)
            let index = publicHTML.appendingPathComponent("index.php")
            if let php = try? String(contentsOf: index, encoding: .utf8) {
                try HostingCopier.repointIndex(php, appFolder: app, laravel: type == .laravel).write(to: index, atomically: true, encoding: .utf8)
                append("\(lrm("public_html/index.php")) حالا برنامه را از \(lrm("../\(app)/")) بارگذاری می‌کند", .system)
            }
            // storage:link needs a shell; ship a real folder the host can write to instead.
            let link = publicHTML.appendingPathComponent("storage")
            if (try? link.checkResourceIsReachable()) == nil || ((try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil) {
                try? fm.removeItem(at: link)
            }
        }

        if type == .laravel {
            let env = HostingCopier.productionEnv(from: src, appURL: HostingCopier.normalizedURL(siteAddress))
            try env.write(to: target.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
            append("\(lrm("\(app)/.env")) ساخته شد (APP_ENV=production، APP_DEBUG=false، APP_KEY تازه).", .system)
            if let url = env.components(separatedBy: "\n").first(where: { $0.hasPrefix("APP_URL=") }),
               HostingCopier.normalizedURL(String(url.dropFirst(8))) == nil {
                append("⚠︎ \(url) آدرس معتبری نیست — APP_URL را در \(lrm(".env")) روی هاست درست کنید.", .system)
            }
        }

        return try await finish(stage: stage)
    }

    private func finish(stage: URL) async throws -> URL {
        let fm = FileManager.default
        try HostingCopier.readme(project: project.name, layout: layoutDescription, checks: checks)
            .write(to: stage.appendingPathComponent("README-HOSTING.txt"), atomically: true, encoding: .utf8)

        phase = .running("فشرده‌سازی")
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stamp = Self.stampFormatter.string(from: Date())
        let zip = outputDirectory.appendingPathComponent("\(packageName)-hosting-\(stamp).zip")
        try? fm.removeItem(at: zip)
        try await exec("/usr/bin/zip", ["-qry", "-X", zip.path, "."], in: stage, quiet: true)
        let size = (try? zip.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "?"
        append("حجم zip: \(size)", .system)
        return zip
    }

    // MARK: Helpers

    private func staticOutput() -> URL? {
        for name in ["dist", "build", "out"] {
            let dir = project.url.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path) { return dir }
        }
        return nil
    }

    private func checkCancelled() throws {
        if cancelled { throw HostingError("لغو شد") }
    }

    private func relative(_ url: URL) -> String {
        String(url.path.dropFirst(project.url.path.count + 1))
    }

    /// Runs a tool, streaming its output into the log; throws on a non-zero exit.
    private func exec(_ program: String, _ args: [String], in dir: URL, quiet: Bool = false) async throws {
        let path = ExecutableLocator.searchPath(for: project.url)
        guard let exe = ExecutableLocator.find(program, in: path) else {
            throw HostingError("\(program) پیدا نشد. نصبش کنید (مثلاً brew install \(program)) و دوباره امتحان کنید.")
        }
        append("$ \(([exe.lastPathComponent] + args).joined(separator: " "))", .system)
        let process = Process()
        process.executableURL = exe
        process.arguments = args
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path.joined(separator: ":")
        env["COMPOSER_NO_INTERACTION"] = "1"
        env["FORCE_COLOR"] = "0"
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let group = DispatchGroup()
        for stream in [LogLine.Stream.stdout, .stderr] {
            let pipe = Pipe()
            if stream == .stdout { process.standardOutput = pipe } else { process.standardError = pipe }
            let splitter = LineSplitter()
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                let lines = data.isEmpty ? splitter.flush() : splitter.feed(data)
                if data.isEmpty { handle.readabilityHandler = nil; group.leave() }
                if !lines.isEmpty && !quiet { Task { @MainActor in self?.append(lines, stream) } }
            }
        }

        let status: Int32 = try await withCheckedThrowingContinuation { cont in
            group.enter()
            process.terminationHandler = { _ in group.leave() }
            do { try process.run(); self.current = process } catch {
                group.leave(); group.leave(); group.leave()
                cont.resume(throwing: error)
                return
            }
            group.notify(queue: .main) { cont.resume(returning: process.terminationStatus) }
        }
        current = nil
        if status != 0 { throw HostingError("\(exe.lastPathComponent) با کد \(status) متوقف شد") }
    }

    private func append(_ text: String, _ stream: LogLine.Stream) { append([text], stream) }

    private func append(_ lines: [String], _ stream: LogLine.Stream) {
        for line in lines {
            log.append(LogLine(id: nextLineID, text: line, stream: stream))
            nextLineID += 1
        }
        if log.count > 5000 { log.removeFirst(log.count - 5000) }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()

    /// `deploy/build.sh` or `deploy/<target>/build.sh`.
    static func findProjectScript(in dir: URL) -> URL? {
        let fm = FileManager.default
        let deploy = dir.appendingPathComponent("deploy")
        let direct = deploy.appendingPathComponent("build.sh")
        if fm.fileExists(atPath: direct.path) { return direct }
        let subs = ((try? fm.contentsOfDirectory(atPath: deploy.path)) ?? []).sorted()
        for sub in subs {
            let candidate = deploy.appendingPathComponent(sub).appendingPathComponent("build.sh")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The zip a project script just produced.
    static func newestZip(in dir: URL, since: Date) -> URL? {
        let skip: Set<String> = ["node_modules", "vendor", ".git"]
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else { return nil }
        var best: (URL, Date)?
        for case let url as URL in walker {
            if skip.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
            if walker.level > 4 { walker.skipDescendants(); continue }
            guard url.pathExtension == "zip",
                  let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date >= since.addingTimeInterval(-1) else { continue }
            if best == nil || date > best!.1 { best = (url, date) }
        }
        return best?.0
    }
}

struct FlaggedFile: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let reason: String
    var excluded: Bool
}

struct HostingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// File-level pieces of packaging, kept free of UI state so they are easy to test.
enum HostingCopier {
    /// Anywhere in the tree.
    static let skippedNames: Set<String> = [".git", ".DS_Store", "node_modules", "__pycache__", ".idea", ".vscode", ".venv", "venv", ".pytest_cache", ".phpunit.cache"]

    /// Relative to the project root.
    static func skippedPaths(for type: ProjectType, skipVendor: Bool) -> [String] {
        var paths = ["public/hot", "public/storage"]
        if type == .laravel {
            paths += ["dist", "deploy", "tests", "storage/app", "storage/logs", "storage/framework/cache", "storage/framework/sessions",
                      "storage/framework/views", "storage/framework/testing", "bootstrap/cache", "database/database.sqlite"]
        }
        if skipVendor { paths.append("vendor") }
        return paths
    }

    static func isSecretEnv(_ name: String) -> Bool {
        name.hasPrefix(".env") && name != ".env.example" && !name.hasSuffix(".example")
    }

    @discardableResult
    static func copy(from src: URL, to dst: URL, type: ProjectType, skipVendor: Bool, excluding extra: Set<String> = []) throws -> Int {
        let fm = FileManager.default
        let skipped = Set(skippedPaths(for: type, skipVendor: skipVendor)).union(extra)
        var count = 0

        func walk(_ dir: URL, _ rel: String) throws {
            let out = rel.isEmpty ? dst : dst.appendingPathComponent(rel)
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            for name in try fm.contentsOfDirectory(atPath: dir.path) {
                let childRel = rel.isEmpty ? name : "\(rel)/\(name)"
                if skippedNames.contains(name) || skipped.contains(childRel) || name.hasSuffix(".zip") { continue }
                if isSecretEnv(name) || name.hasSuffix(".pyc") || name.hasSuffix(".log") { continue }
                let child = dir.appendingPathComponent(name)
                let attrs = try fm.attributesOfItem(atPath: child.path)
                switch attrs[.type] as? FileAttributeType {
                case .typeSymbolicLink:
                    continue // links break once uploaded
                case .typeDirectory:
                    try walk(child, childRel)
                default:
                    try fm.copyItem(at: child, to: out.appendingPathComponent(name))
                    count += 1
                }
            }
        }
        try walk(src, "")
        return count
    }

    static let dumpExtensions: Set<String> = ["sql", "gz", "tgz", "bz2", "xz", "7z", "rar", "bak", "hostbak", "old", "orig",
                                              "sqlite", "sqlite3", "db", "dump", "swp"]

    /// Backups and dumps are left out by default: in a web root they are plain downloads.
    /// Secret-looking files are only flagged — the site may need them, and .php is executed, not served.
    static func flaggedFiles(in src: URL, type: ProjectType) -> [FlaggedFile] {
        let fm = FileManager.default
        let skipped = Set(skippedPaths(for: type, skipVendor: true))
        var result: [FlaggedFile] = []

        func walk(_ dir: URL, _ rel: String) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            for name in names.sorted() {
                let childRel = rel.isEmpty ? name : "\(rel)/\(name)"
                if skippedNames.contains(name) || skipped.contains(childRel) || isSecretEnv(name) || name.hasSuffix(".zip") { continue }
                let child = dir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDir) else { continue }
                let lower = name.lowercased()
                if isDir.boolValue {
                    if lower == "backup" || lower == "backups" || lower == "dumps" {
                        result.append(FlaggedFile(path: childRel, reason: "پوشهٔ بکاپ", excluded: true))
                    } else {
                        walk(child, childRel)
                    }
                } else if dumpExtensions.contains((lower as NSString).pathExtension) || lower.hasSuffix("~") {
                    result.append(FlaggedFile(path: childRel, reason: "بکاپ، فایل فشرده یا خروجی دیتابیس", excluded: true))
                } else if !lower.contains("example") && !lower.contains("sample"),
                          lower.contains("secret") || lower.contains("credential") || ["pem", "key", "p12"].contains((lower as NSString).pathExtension) {
                    result.append(FlaggedFile(path: childRel, reason: "ممکن است رمز داشته باشد — مطمئن شوید نسخهٔ مخصوص هاست است", excluded: false))
                }
            }
        }
        walk(src, "")
        return result
    }

    static func recreateLaravelRuntimeDirs(in app: URL) {
        for dir in ["storage/logs", "storage/framework/cache/data", "storage/framework/sessions",
                    "storage/framework/views", "storage/app/public", "storage/app/private", "bootstrap/cache"] {
            let url = app.appendingPathComponent(dir)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? "*\n!.gitignore\n".write(to: url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        }
    }

    /// Makes public_html/index.php load the app from ../<app>/ and tells Laravel where its public files are.
    static func repointIndex(_ php: String, appFolder: String, laravel: Bool) -> String {
        var out = php
            .replacingOccurrences(of: "__DIR__.'/../", with: "__DIR__.'/../\(appFolder)/")
            .replacingOccurrences(of: "__DIR__ . '/../", with: "__DIR__ . '/../\(appFolder)/")
            .replacingOccurrences(of: "__DIR__.\"/../", with: "__DIR__.\"/../\(appFolder)/")
            .replacingOccurrences(of: "dirname(__DIR__)", with: "(__DIR__ . '/../\(appFolder)')")
        guard laravel, let range = out.range(of: #"\$app\s*=\s*require_once[^;]+;"#, options: .regularExpression) else { return out }
        out.insert(contentsOf: """

            // Bana: public files live in public_html, the app in ../\(appFolder)/
            if (method_exists($app, 'usePublicPath')) { $app->usePublicPath(__DIR__); } else { $app->instance('path.public', __DIR__); }
            """, at: range.upperBound)
        return out
    }

    /// .env for the host: .env.production.example or .env.example, production-safe, fresh key.
    /// "example.com" → "https://example.com"; nil when empty or not a usable host.
    static func normalizedURL(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        // Check the typed host: URL(string:) silently punycodes non-ASCII names.
        let afterScheme = t.components(separatedBy: "://").last ?? ""
        let host = String(afterScheme.prefix { $0 != "/" && $0 != ":" })
        guard host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              host.contains(".") || host == "localhost", URL(string: t) != nil else { return nil }
        return t
    }

    static func productionEnv(from src: URL, appURL: String? = nil) -> String {
        let text = [".env.production.example", ".env.example"]
            .lazy.compactMap { try? String(contentsOf: src.appendingPathComponent($0), encoding: .utf8) }.first ?? ""
        var key = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, key.count, &key)
        var values = ["APP_ENV": "production", "APP_DEBUG": "false", "APP_KEY": "base64:" + Data(key).base64EncodedString()]
        if let appURL { values["APP_URL"] = appURL }

        var seen = Set<String>()
        var lines = text.components(separatedBy: "\n").map { line -> String in
            guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#") else { return line }
            let name = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard let value = values[name] else { return line }
            seen.insert(name)
            return "\(name)=\(value)"
        }
        for (name, value) in values.sorted(by: { $0.key < $1.key }) where !seen.contains(name) { lines.insert("\(name)=\(value)", at: 0) }
        return lines.joined(separator: "\n")
    }

    static func readme(project: String, layout: [String], checks: [String]) -> String {
        """
        \(project) — بستهٔ آمادهٔ هاست (ساخته‌شده با بنا)

        چیدمان
        \(layout.map { "  • " + $0 }.joined(separator: "\n"))

        پیش از راه‌اندازی
        \(checks.map { "  • " + $0 }.joined(separator: "\n"))

        مراحل
          ۱. فایل zip را در File Manager هاست، در پوشهٔ دامنه آپلود و Extract کنید.
          ۲. اگر پوشهٔ برنامه جدا از public_html است، آن را بیرون از public_html نگه دارید.
          ۳. فایل .env را باز کنید و مشخصات دیتابیس را وارد کنید.
          ۴. نسخهٔ PHP را در پنل هاست مطابق نیاز پروژه انتخاب کنید.
        """
    }
}

extension HostingJob: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
