import XCTest
@testable import Bana

@MainActor
final class EnvTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testRoundTripKeepsCommentsOrderAndQuotes() {
        let text = "# App\nAPP_NAME=\"Pasargad Saze\"\nAPP_KEY=\n\n# DB\nDB_PASSWORD=p@ss=word\nexport PATH_X=/a\n"
        var doc = EnvDocument(text: text)
        XCTAssertEqual(doc.text, text)
        XCTAssertEqual(doc.value("DB_PASSWORD"), "p@ss=word", "only the first = splits")
        XCTAssertTrue(doc.lines.first { $0.key == "DB_PASSWORD" }!.isSecret)
        XCTAssertFalse(doc.lines.first { $0.key == "APP_NAME" }!.isSecret)
        doc.set("APP_KEY", "base64:abc")
        doc.set("NEW", "1")
        XCTAssertEqual(doc.text, "# App\nAPP_NAME=\"Pasargad Saze\"\nAPP_KEY=base64:abc\n\n# DB\nDB_PASSWORD=p@ss=word\nexport PATH_X=/a\nNEW=1\n")
    }

    func testFindsRootAndDeployEnvFilesEnvFirst() throws {
        for path in [".env.example", ".env", "deploy/directadmin/.env.host", "deploy/.env.staging", "public/.env.nope"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "A=1".write(to: url, atomically: true, encoding: .utf8)
        }
        let found = EnvFiles.find(in: root).map { String($0.path.dropFirst(root.path.count + 1)) }
        XCTAssertEqual(found, [".env", ".env.example", "deploy/.env.staging", "deploy/directadmin/.env.host"])
    }

    func testWriteKeepsPermissionsAndNewFilesAreOwnerOnly() throws {
        let fresh = root.appendingPathComponent(".env")
        try EnvFiles.write("A=1\n", to: fresh)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: fresh.path)[.posixPermissions] as? Int, 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fresh.path)
        try EnvFiles.write("A=2\n", to: fresh)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: fresh.path)[.posixPermissions] as? Int, 0o644)
    }

    func testCustomHostEnvIsSavedAndShipped() async throws {
        let dir = root.appendingPathComponent("crm")
        for (path, body) in [("artisan", ""), ("public/index.php", "<?php $app = require_once __DIR__.'/../bootstrap/app.php';"),
                             (".env", "DB_PASSWORD=local-secret\n"), (".env.example", "APP_ENV=local\nAPP_KEY=\n")] {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        let project = Project(url: dir, detectedType: .laravel, relativePath: "crm")
        defer { HostingEnvStore.delete(for: project) }

        let first = HostingJob(project: project, type: .laravel)
        XCTAssertFalse(first.useCustomEnv)
        XCTAssertTrue(first.draftEnv().contains("APP_ENV=production"), "draft starts from the generated one")
        try first.saveCustomEnv("APP_ENV=production\nAPP_KEY=\nDB_HOST=db.example.com\nDB_PASSWORD=host-secret\n")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: HostingEnvStore.url(for: project).path)[.posixPermissions] as? Int, 0o600)

        let job = HostingJob(project: project, type: .laravel) // a later session picks it up
        XCTAssertTrue(job.useCustomEnv)
        job.outputDirectory = root.appendingPathComponent("out")
        job.start()
        try await HostingTests.wait(job)
        guard case .finished(let zip?) = job.phase else { return XCTFail("\(job.phase)") }
        let env = try HostingTests.read("crm/.env", in: zip)
        XCTAssertTrue(env.contains("DB_HOST=db.example.com"))
        XCTAssertTrue(env.contains("DB_PASSWORD=host-secret"))
        XCTAssertTrue(env.contains("APP_KEY=base64:"), "empty APP_KEY is filled")
        XCTAssertFalse(env.contains("local-secret"))

        job.forgetCustomEnv()
        XCTAssertNil(HostingEnvStore.load(for: project))
    }

    func testPlainPHPNeverShipsCustomEnv() {
        let project = Project(url: root, detectedType: .php, relativePath: ".")
        XCTAssertFalse(HostingJob(project: project, type: .php).supportsCustomEnv, ".env in public_html would be downloadable")
    }
}
