import XCTest
import SwiftUI
@testable import Bana

/// Opt-in: TEST_RUNNER_BANA_SNAPSHOT_DIR=/path renders key screens to PNG (light + dark) for a visual check.
@MainActor
final class SnapshotTests: XCTestCase {
    func testRenderScreens() async throws {
        let out = try XCTUnwrap(ProcessInfo.processInfo.environment["BANA_SNAPSHOT_DIR"].map { $0 } ?? { throw XCTSkip("set BANA_SNAPSHOT_DIR") }())
        let root = ProcessInfo.processInfo.environment["LAUNCHER_REAL_ROOT"] ?? NSHomeDirectory()
        let projects = ProjectScanner.scan(root: URL(fileURLWithPath: root))
        let store = ProjectStore.shared
        let laravel = try XCTUnwrap(projects.first { $0.detectedType == .laravel } ?? projects.first)
        let plain = projects.first { $0.relativePath.hasSuffix("fanal-app-pasargad/php") } ?? laravel

        store.start(laravel)
        for _ in 0..<40 where store.runtime(for: laravel).status != .running { try await Task.sleep(nanoseconds: 250_000_000) }
        defer { store.stop(laravel) }

        let cards = VStack(alignment: .leading, spacing: 0) {
            ForEach(projects.prefix(5)) { p in
                ProjectCard(runtime: store.runtime(for: p), project: p).padding(.horizontal, 10)
                Divider()
            }
        }
        .frame(width: 300)

        let screens: [(String, AnyView, CGSize)] = [
            ("detail", AnyView(ProjectDetailView(project: laravel, runtime: store.runtime(for: laravel))), CGSize(width: 900, height: 620)),
            ("hosting", AnyView(HostingSheet(job: HostingJob(project: plain, type: plain.detectedType))), CGSize(width: 640, height: 480)),
            ("cards", AnyView(cards), CGSize(width: 300, height: 330)),
        ]
        for (name, view, size) in screens {
            for dark in [false, true] {
                let host = NSHostingView(rootView: view.environmentObject(store).persianUI()
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor)))
                host.frame = CGRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 400_000_000)
                host.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: out).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
