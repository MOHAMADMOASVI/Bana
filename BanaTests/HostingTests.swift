import XCTest
@testable import Bana

@MainActor
final class HostingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hosting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func make(_ path: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    static func wait(_ job: HostingJob, seconds: Double = 600) async throws {
        for _ in 0..<Int(seconds * 4) {
            if case .running = job.phase { try await Task.sleep(nanoseconds: 250_000_000); continue }
            if job.phase == .ready { try await Task.sleep(nanoseconds: 250_000_000); continue }
            return
        }
    }

    static func entries(_ zip: URL) throws -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        p.arguments = ["-1", zip.path]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile() // read before waiting: a full pipe blocks zipinfo
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    static func read(_ entry: String, in zip: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", zip.path, entry]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func testLaravelSplitPackage() async throws {
        try make("crm/artisan")
        try make("crm/app/Models/User.php")
        try make("crm/public/.htaccess")
        try make("crm/public/index.php", """
        <?php
        if (file_exists($maintenance = __DIR__.'/../storage/framework/maintenance.php')) { require $maintenance; }
        require __DIR__.'/../vendor/autoload.php';
        $app = require_once __DIR__.'/../bootstrap/app.php';
        $app->handleRequest(Request::capture());
        """)
        try make("crm/.env", "DB_PASSWORD=super-secret-local")
        try make("crm/.env.example", "APP_NAME=CRM\nAPP_ENV=local\nAPP_KEY=\nAPP_DEBUG=true\nDB_HOST=127.0.0.1\n")
        try make("crm/storage/logs/laravel.log")
        try make("crm/storage/app/private/uploads/photo.jpg")
        try make("crm/tests/Feature/ExampleTest.php")
        try make("crm/node_modules/x/index.js")
        try make("crm/.git/HEAD")

        let project = Project(url: root.appendingPathComponent("crm"), detectedType: .laravel, relativePath: "crm")
        let job = HostingJob(project: project, type: .laravel)
        XCTAssertNil(job.projectScript)
        job.outputDirectory = root.appendingPathComponent("out")
        job.siteAddress = "app.example.com/"
        job.start()
        try await Self.wait(job)
        guard case .finished(let zip?) = job.phase else { return XCTFail("\(job.phase)\n" + job.log.map(\.text).joined(separator: "\n")) }

        let files = try Self.entries(zip)
        XCTAssertTrue(files.contains("crm/app/Models/User.php"))
        XCTAssertTrue(files.contains("public_html/index.php"))
        XCTAssertTrue(files.contains("public_html/.htaccess"))
        XCTAssertTrue(files.contains("crm/storage/framework/sessions/.gitignore"))
        XCTAssertTrue(files.contains("crm/storage/app/private/.gitignore"))
        XCTAssertFalse(files.contains { $0.hasSuffix("photo.jpg") }, "local uploads stay local")
        XCTAssertTrue(files.contains("README-HOSTING.txt"))
        XCTAssertFalse(files.contains { $0.hasPrefix("crm/public/") }, "public/ moves to public_html/")
        XCTAssertFalse(files.contains { $0.contains("node_modules") || $0.contains(".git/") || $0.hasPrefix("crm/tests") || $0.hasSuffix(".log") })

        let env = try Self.read("crm/.env", in: zip)
        XCTAssertFalse(env.contains("super-secret-local"), "local .env must never ship")
        XCTAssertTrue(env.contains("APP_DEBUG=false"))
        XCTAssertTrue(env.contains("APP_ENV=production"))
        XCTAssertTrue(env.contains("APP_KEY=base64:"))
        XCTAssertTrue(env.contains("APP_NAME=CRM"))
        XCTAssertTrue(env.contains("APP_URL=https://app.example.com"))
        XCTAssertNil(HostingCopier.normalizedURL("https://دامنه.com"))

        let index = try Self.read("public_html/index.php", in: zip)
        XCTAssertTrue(index.contains("__DIR__.'/../crm/vendor/autoload.php'"))
        XCTAssertTrue(index.contains("__DIR__.'/../crm/bootstrap/app.php'"))
        XCTAssertTrue(index.contains("usePublicPath(__DIR__)"))
        XCTAssertFalse(index.contains("'/../storage"))
    }

    func testPlainPHPLeavesBackupsOutAndFlagsSecrets() async throws {
        try make("php/index.php", "<?php echo 1;")
        try make("php/config/secrets.php", "<?php return ['pass' => 'x'];")
        try make("php/config/secrets.example.php")
        try make("php/config/secrets.php.hostbak", "pass=x")
        try make("php/install_full.sql")
        try make("php/backups/old.tar.gz")
        try make("php/includes/backup.php")
        let project = Project(url: root.appendingPathComponent("php"), detectedType: .php, relativePath: "shop/php")
        let job = HostingJob(project: project, type: .php)
        XCTAssertEqual(job.flagged.map(\.path), ["backups", "config/secrets.php", "config/secrets.php.hostbak", "install_full.sql"])
        XCTAssertEqual(job.flagged.filter(\.excluded).map(\.path), ["backups", "config/secrets.php.hostbak", "install_full.sql"])
        XCTAssertTrue(job.packageName.hasSuffix("-php"), "generic folder name gets its parent's")

        job.outputDirectory = root.appendingPathComponent("out")
        job.start()
        try await Self.wait(job)
        guard case .finished(let zip?) = job.phase else { return XCTFail("\(job.phase)") }
        let files = try Self.entries(zip)
        XCTAssertTrue(files.contains("public_html/index.php"))
        XCTAssertTrue(files.contains("public_html/includes/backup.php"), "code named backup is not a backup")
        XCTAssertTrue(files.contains("public_html/config/secrets.php"), "flagged but kept")
        XCTAssertFalse(files.contains { $0.contains("backups/") || $0.hasSuffix(".sql") || $0.hasSuffix(".hostbak") })
    }

    func testProjectScriptIsPreferredAndItsZipFound() async throws {
        try make("site/artisan")
        try make("site/deploy/directadmin/build.sh", "#!/bin/bash\nset -e\nmkdir -p dist\necho building\ncd dist && echo hi > a.txt && /usr/bin/zip -q site.zip a.txt\n")
        chmod(root.appendingPathComponent("site/deploy/directadmin/build.sh").path, 0o755)
        let project = Project(url: root.appendingPathComponent("site"), detectedType: .laravel, relativePath: "site")
        let job = HostingJob(project: project, type: .laravel)
        XCTAssertTrue(job.useProjectScript)
        job.start()
        try await Self.wait(job, seconds: 30)
        guard case .finished(let zip?) = job.phase else { return XCTFail("\(job.phase)") }
        XCTAssertEqual(zip.lastPathComponent, "site.zip")
        XCTAssertTrue(job.log.contains { $0.text == "building" })
    }

    func testFailingStepReportsError() async throws {
        try make("bad/deploy/build.sh", "#!/bin/bash\necho nope >&2\nexit 3\n")
        chmod(root.appendingPathComponent("bad/deploy/build.sh").path, 0o755)
        let job = HostingJob(project: Project(url: root.appendingPathComponent("bad"), detectedType: .php, relativePath: "bad"), type: .php)
        job.start()
        try await Self.wait(job, seconds: 30)
        XCTAssertEqual(job.phase, .failed("build.sh با کد 3 متوقف شد"))
    }
}
