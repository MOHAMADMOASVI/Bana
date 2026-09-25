import XCTest
@testable import Bana

final class DatabaseTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testConfigFromLaravelEnv() throws {
        try "DB_CONNECTION=mysql\nDB_HOST=localhost\nDB_PORT=8889\nDB_DATABASE='shop'\nDB_USERNAME=\"root\"\nDB_PASSWORD=\"p#ss w\"\n"
            .write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let c = try XCTUnwrap(DBConfig.fromEnv(in: root))
        XCTAssertEqual(c.driver, .mysql)
        XCTAssertEqual(c.port, 8889)
        XCTAssertEqual(c.database, "shop")
        XCTAssertEqual(c.password, "p#ss w")

        try "DB_CONNECTION=sqlite\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        XCTAssertEqual(DBConfig.fromEnv(in: root)?.path, root.appendingPathComponent("database/database.sqlite").path)
        try "DB_CONNECTION=pgsql\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        XCTAssertNil(DBConfig.fromEnv(in: root))
    }

    func testManualConnectionIsOwnerOnly() throws {
        let project = Project(url: root, detectedType: .php, relativePath: ".")
        defer { DBConnectionStore.delete(for: project) }
        var c = DBConfig(); c.database = "x"; c.password = "secret"
        try DBConnectionStore.save(c, for: project)
        XCTAssertEqual(DBConnectionStore.load(for: project), c)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: DBConnectionStore.url(for: project).path)[.posixPermissions] as? Int, 0o600)
    }

    func testStripDefiners() throws {
        let file = root.appendingPathComponent("d.sql")
        try """
        CREATE TABLE a (id int);
        /*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
        CREATE DEFINER=`root`@`%` TRIGGER t BEFORE INSERT ON a FOR EACH ROW SET @x = 1;
        CREATE DEFINER='admin'@'127.0.0.1' PROCEDURE p() SELECT 1;
        INSERT INTO a VALUES (1);

        """.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try SQLFilter.stripDefiners(in: file), 3)
        let out = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(out.contains("DEFINER="))
        XCTAssertTrue(out.contains("CREATE TRIGGER t BEFORE INSERT"))
        XCTAssertTrue(out.contains("SQL SECURITY DEFINER"), "only the user@host clause goes")
        XCTAssertTrue(out.contains("INSERT INTO a VALUES (1);"))
    }

    func testSQLiteExportImportRoundTrip() async throws {
        let src = root.appendingPathComponent("app.sqlite").path
        let setup = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/sqlite3"), [src,
            "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO users(name) VALUES ('علی'),('Sara'); CREATE TABLE posts(id INTEGER);"])
        XCTAssertEqual(setup.status, 0, setup.stderr)

        var c = DBConfig(); c.driver = .sqlite; c.path = src
        let client = DatabaseClient(config: c)
        let version = try await client.serverVersion()
        XCTAssertTrue(version.hasPrefix("SQLite"))
        let tables = try await client.tables()
        XCTAssertEqual(tables, [TableInfo(name: "posts", rows: 0, bytes: 0), TableInfo(name: "users", rows: 2, bytes: 0)])

        let dump = try await client.export(to: root.appendingPathComponent("app.sql.gz"),
                                           options: .init(includeData: true, forHosting: false, gzip: true)) { _ in }
        XCTAssertEqual(dump.lastPathComponent, "app.sql.gz")

        var c2 = c; c2.path = root.appendingPathComponent("copy.sqlite").path
        let copy = DatabaseClient(config: c2)
        try await copy.importFile(dump) { _ in }
        let copied = try await copy.tables()
        XCTAssertEqual(copied.map(\.rows), [0, 2])
        let name = try await CommandRunner.run(URL(fileURLWithPath: "/usr/bin/sqlite3"), [c2.path, "SELECT name FROM users WHERE id=1"])
        XCTAssertEqual(name.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "علی")
    }

    func testImportErrorIsReported() async throws {
        var c = DBConfig(); c.driver = .sqlite; c.path = root.appendingPathComponent("e.sqlite").path
        let bad = root.appendingPathComponent("bad.sql")
        try "THIS IS NOT SQL;".write(to: bad, atomically: true, encoding: .utf8)
        do {
            try await DatabaseClient(config: c).importFile(bad) { _ in }
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.lowercased().contains("syntax"), error.localizedDescription)
        }
    }

    /// Opt-in, against the real local MySQL of the Laravel project under LAUNCHER_REAL_ROOT:
    /// reads and exports the real database, imports only into a temporary one that is dropped.
    func testMySQLAgainstRealProjectReadOnly() async throws {
        let rootPath = ProcessInfo.processInfo.environment["LAUNCHER_REAL_ROOT"]
        try XCTSkipIf(rootPath == nil, "opt-in")
        let laravel = try XCTUnwrap(ProjectScanner.scan(root: URL(fileURLWithPath: rootPath!)).first { $0.detectedType == .laravel })
        let real = try XCTUnwrap(DBConfig.fromEnv(in: laravel.url))
        try XCTSkipIf(real.driver != .mysql)
        let client = DatabaseClient(config: real)
        let version = try await client.serverVersion()
        let before = try await client.tables()
        XCTAssertFalse(before.isEmpty)

        let dump = try await client.export(to: root.appendingPathComponent("real.sql"),
                                           options: .init(includeData: true, forHosting: true, gzip: true)) { _ in }
        let tmpName = "bana_tmp_\(Int.random(in: 100000...999999))"
        try await client.createDatabase(tmpName)
        do {
            var tmp = real; tmp.database = tmpName
            let tmpClient = DatabaseClient(config: tmp)
            try await tmpClient.importFile(dump) { _ in }
            let copied = try await tmpClient.tables()
            XCTAssertEqual(copied.map(\.name), before.map(\.name))
        } catch {
            try? await client.dropDatabase(tmpName)
            throw error
        }
        try await client.dropDatabase(tmpName)

        let after = try await client.tables()
        XCTAssertEqual(after.map(\.name), before.map(\.name), "real database untouched")
        print("MYSQL OK: \(version), \(before.count) tables, dump \((try? dump.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) bytes")
    }
}
