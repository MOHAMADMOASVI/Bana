import XCTest
@testable import ProjectLauncher

/// Opt-in smoke test against a real projects folder: TEST_RUNNER_LAUNCHER_REAL_ROOT=/path xcodebuild test …
@MainActor
final class RealProjectsTests: XCTestCase {
    func testStartEveryProject() async throws {
        let rootPath = try XCTUnwrap(ProcessInfo.processInfo.environment["LAUNCHER_REAL_ROOT"].map { $0 }, "set LAUNCHER_REAL_ROOT")
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
}
