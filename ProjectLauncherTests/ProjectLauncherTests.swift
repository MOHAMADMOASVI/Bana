import XCTest
@testable import ProjectLauncher

final class DetectionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func make(_ path: String, _ contents: String = "") throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testDetectsEachTypeAndPrefersPHPForLaravel() throws {
        try make("shop/composer.json", "{}")
        try make("shop/package.json", "{}")          // Laravel has both → PHP
        try make("api/main.py")
        try make("web/package.json", "{}")
        try make("stack/docker-compose.yml", "services: {}")
        try make("clients/acme/index.php")          // nested
        try make("web/node_modules/x/package.json") // must be skipped
        try make("notes/readme.md")                 // not a project

        let found = Dictionary(uniqueKeysWithValues: ProjectScanner.scan(root: root).map { ($0.relativePath, $0.detectedType) })
        XCTAssertEqual(found, ["shop": .php, "api": .python, "web": .node, "stack": .docker, "clients/acme": .php])
    }

    func testCommands() throws {
        try make("lara/composer.json", "{}")
        try make("lara/public/index.php")
        try make("vite/package.json", #"{"scripts":{"dev":"vite"}}"#)
        try make("dock/compose.yaml", "services:\n  web:\n    ports:\n      - \"8088:80\"\n")
        let projects = Dictionary(uniqueKeysWithValues: ProjectScanner.scan(root: root).map { ($0.name, $0) })

        let php = CommandBuilder.spec(for: projects["lara"]!, type: .php, port: 8001, customCommand: nil)
        XCTAssertEqual(php.program, "php")
        XCTAssertEqual(Array(php.arguments.suffix(4)), ["-S", "0.0.0.0:8001", "-t", "public"])

        let node = CommandBuilder.spec(for: projects["vite"]!, type: .node, port: 5174, customCommand: nil)
        XCTAssertEqual(node.arguments, ["run", "dev", "--", "--host", "0.0.0.0", "--port", "5174"])

        let py = CommandBuilder.spec(for: projects["lara"]!, type: .python, port: 9000, customCommand: nil)
        XCTAssertEqual(py.arguments, ["main:app", "--host", "0.0.0.0", "--port", "9000"])

        try make("fast/main.py", "from fastapi import FastAPI\napp = FastAPI()\n")
        try make("flask/main.py", "from flask import Flask\napp = Flask(__name__)\n")
        try make("script/main.py", "import argparse\nprint('hi')\n")
        let py3 = { (name: String) in CommandBuilder.spec(for: Project(url: self.root.appendingPathComponent(name), detectedType: .python, relativePath: name), type: .python, port: 9001, customCommand: nil) }
        XCTAssertEqual(py3("fast").program, "uvicorn")
        XCTAssertEqual(py3("flask").arguments, ["--app", "main", "run", "--host", "0.0.0.0", "--port", "9001"])
        XCTAssertEqual(py3("script").program, "python3")
        XCTAssertNil(py3("script").port)

        XCTAssertEqual(CommandBuilder.spec(for: projects["dock"]!, type: .docker, port: 1, customCommand: nil).port, 8088)

        let custom = CommandBuilder.spec(for: projects["lara"]!, type: .php, port: 7000,
                                         customCommand: #"php artisan serve --host=0.0.0.0 --port={port} --name "a b""#)
        XCTAssertEqual(custom.arguments, ["artisan", "serve", "--host=0.0.0.0", "--port=7000", "--name", "a b"])
    }

    func testLineSplitterStripsANSIAndCarriageReturns() {
        let s = LineSplitter()
        XCTAssertEqual(s.feed(Data("\u{1B}[32mready\u{1B}[0m\npart".utf8)), ["ready"])
        XCTAssertEqual(s.feed(Data("ial\n10%\r50%\r100%\n".utf8)), ["partial", "100%"])
        // A multi-byte character split across chunks survives.
        let bytes = Array("سلام\n".utf8)
        XCTAssertEqual(s.feed(Data(bytes[..<3])), [])
        XCTAssertEqual(s.feed(Data(bytes[3...])), ["سلام"])
    }
}

final class NetworkTests: XCTestCase {
    func testPortFinderSkipsBoundPort() throws {
        let port = try XCTUnwrap(PortFinder.findFree(startingAt: 18_500))
        XCTAssertTrue(PortFinder.isFree(port))
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(fd, 1), 0)
        XCTAssertFalse(PortFinder.isFree(port))
        XCTAssertTrue(PortFinder.isListening(port))
        XCTAssertNotEqual(PortFinder.findFree(startingAt: port), port)
    }

    func testQRCode() {
        XCTAssertNotNil(QRCodeGenerator.image(for: "http://192.168.1.20:8000"))
    }

    func testLocalIPIsIPv4WhenPresent() {
        if let ip = NetworkInfo.localIPv4() {
            XCTAssertEqual(ip.split(separator: ".").count, 4)
            XCTAssertFalse(ip.hasPrefix("127."))
        }
    }
}

/// End to end inside the App Sandbox: exec Homebrew php, bind 0.0.0.0, serve, stop the tree.
@MainActor
final class RuntimeTests: XCTestCase {
    func testPHPServerStartsServesAndStops() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "<?php echo 'hello-launcher';".write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        let project = Project(url: dir, detectedType: .php, relativePath: ".")
        let path = ExecutableLocator.searchPath(for: dir)
        try XCTSkipIf(ExecutableLocator.find("php", in: path) == nil, "php not installed")

        let port = try XCTUnwrap(PortFinder.findFree(startingAt: 18_600))
        let rt = ProjectRuntime()
        rt.start(spec: CommandBuilder.spec(for: project, type: .php, port: port, customCommand: nil), in: dir, searchPath: path)

        for _ in 0..<40 where rt.status != .running {
            if case .failed = rt.status { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertEqual(rt.status, .running, rt.log.map(\.text).joined(separator: "\n"))

        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello-launcher")

        let stopped = expectation(description: "stopped")
        rt.stop { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 8)
        XCTAssertEqual(rt.status, .stopped)
        XCTAssertFalse(PortFinder.isListening(port))
        XCTAssertTrue(rt.log.contains { $0.text.contains("GET /") }, "request log should reach the UI")
    }

    func testNpmDevChildTreeIsStopped() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"name":"t","scripts":{"dev":"node server.js"}}"#.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "require('http').createServer((q,r)=>r.end('node-ok')).listen(process.env.PORT,'0.0.0.0',()=>console.log('up'))"
            .write(to: dir.appendingPathComponent("server.js"), atomically: true, encoding: .utf8)
        let project = Project(url: dir, detectedType: .node, relativePath: ".")
        let path = ExecutableLocator.searchPath(for: dir)
        try XCTSkipIf(ExecutableLocator.find("npm", in: path) == nil, "npm not installed")

        let port = try XCTUnwrap(PortFinder.findFree(startingAt: 18_700))
        let rt = ProjectRuntime()
        rt.start(spec: CommandBuilder.spec(for: project, type: .node, port: port, customCommand: nil), in: dir, searchPath: path)
        for _ in 0..<60 where rt.status != .running {
            if case .failed = rt.status { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertEqual(rt.status, .running, rt.log.map(\.text).joined(separator: "\n"))

        let stopped = expectation(description: "stopped")
        rt.stop { stopped.fulfill() }
        await fulfillment(of: [stopped], timeout: 8)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(PortFinder.isListening(port), "node child must not outlive npm")
    }
}
