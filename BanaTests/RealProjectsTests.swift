import XCTest
@testable import Bana

/// Opt-in smoke test against a real projects folder: TEST_RUNNER_LAUNCHER_REAL_ROOT=/path xcodebuild test …
@MainActor
final class RealProjectsTests: XCTestCase {
    private func realRoot() throws -> String {
        let root = ProcessInfo.processInfo.environment["LAUNCHER_REAL_ROOT"]
        try XCTSkipIf(root == nil, "opt-in: TEST_RUNNER_LAUNCHER_REAL_ROOT=/path")
        return root!
    }

    func testStartEveryProject() async throws {
        let rootPath = try realRoot()
        let projects = ProjectScanner.scan(root: URL(fileURLWithPath: rootPath))
        var report = "Found \(projects.count) projects under \(rootPath)\n"
        var reserved = Set<Int>()

        for project in projects {
            let port = try XCTUnwrap(PortFinder.findFree(startingAt: project.detectedType.defaultPort, excluding: reserved))
            reserved.insert(port)
            let spec = CommandBuilder.spec(for: project, type: project.detectedType, port: port, customCommand: nil)
            let rt = ProjectRuntime()
            rt.start(spec: spec, in: project.url, searchPath: ExecutableLocator.searchPath(for: project.url))
            for _ in 0..<120 where rt.status == .starting { try await Task.sleep(nanoseconds: 250_000_000) }

            var http = "-"
            if rt.status == .running, let port = spec.port {
                var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!, timeoutInterval: 20)
                req.httpMethod = "GET"
                if let (data, resp) = try? await URLSession.shared.data(for: req), let h = resp as? HTTPURLResponse {
                    http = "\(h.statusCode), \(data.count) bytes"
                } else { http = "no response" }
            }
            let status = rt.status
            let done = expectation(description: project.name)
            rt.stop { done.fulfill() }
            await fulfillment(of: [done], timeout: 25)
            let freed = spec.port.map { !PortFinder.isListening($0) } ?? true

            report += """

            ■ \(project.relativePath)  [\(project.detectedType.displayName)]
              $ \(spec.displayCommand)
              status: \(status.label)\(status == .running ? "" : " — \(status)")   GET /: \(http)   port freed after stop: \(freed)
              log tail:
            \(rt.log.suffix(6).map { "    " + $0.text.prefix(160) }.joined(separator: "\n"))

            """
        }
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("launcher-report.txt")
        try report.write(to: out, atomically: true, encoding: .utf8)
        print("REPORT: \(out.path)")
    }

    /// Built-in hosting package for every project (no npm build, output to a temp folder).
    func testHostingPackageForEveryProject() async throws {
        let rootPath = try realRoot()
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bana-hosting-real")
        try? FileManager.default.removeItem(at: out)
        var report = ""
        for project in ProjectScanner.scan(root: URL(fileURLWithPath: rootPath)) {
            let job = HostingJob(project: project, type: project.detectedType)
            job.useProjectScript = false
            job.rebuildFrontend = false
            job.outputDirectory = out
            job.start()
            try await HostingTests.wait(job)
            var line = "■ \(project.relativePath) [\(project.detectedType.displayName)] → \(job.phase)"
            if case .finished(let zip?) = job.phase {
                let files = try HostingTests.entries(zip)
                let size = (try? zip.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                line += "\n   \(files.count) entries, \(size / 1024) KB; tops: \(Set(files.map { String($0.split(separator: "/").first ?? "") }).sorted().joined(separator: ", "))"
                let leaked = files.filter { $0.hasSuffix("/.env") || $0 == ".env" }
                    .filter { (try? HostingTests.read($0, in: zip))?.contains("APP_ENV=production") != true }
                line += leaked.isEmpty ? "" : "\n   ⚠︎ non-generated .env: \(leaked)"
                XCTAssertTrue(leaked.isEmpty, "\(project.name): \(leaked)")
            } else {
                line += "\n" + job.log.suffix(8).map { "   " + $0.text }.joined(separator: "\n")
            }
            report += line + "\n"
        }
        try report.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bana-hosting-report.txt"), atomically: true, encoding: .utf8)
    }
}
