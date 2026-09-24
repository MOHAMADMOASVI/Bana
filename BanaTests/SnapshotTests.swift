import XCTest
import SwiftUI
@testable import Bana

/// Opt-in: TEST_RUNNER_BANA_SNAPSHOT_DIR=/path renders key screens to PNG (light + dark) for a visual check.
@MainActor
final class SnapshotTests: XCTestCase {
    func testRenderScreens() async throws {
        let dir = ProcessInfo.processInfo.environment["BANA_SNAPSHOT_DIR"]
        try XCTSkipIf(dir == nil, "opt-in: TEST_RUNNER_BANA_SNAPSHOT_DIR=/path")
        let out = dir!
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

        let savedLanguage = UserDefaults.standard.string(forKey: AppLanguage.key)
        defer { UserDefaults.standard.set(savedLanguage, forKey: AppLanguage.key) } // shared with the installed app
        for lang in AppLanguage.allCases {
        UserDefaults.standard.set(lang.rawValue, forKey: AppLanguage.key)
        let screens: [(String, AnyView, CGSize)] = [
            ("detail", AnyView(ProjectDetailView(project: laravel, runtime: store.runtime(for: laravel))), CGSize(width: 940, height: 680)),
            ("hosting", AnyView(HostingSheet(job: HostingJob(project: plain, type: plain.detectedType))), CGSize(width: 640, height: 500)),
            ("cards", AnyView(cards), CGSize(width: 300, height: 330)),
            ("tile", AnyView(ProjectCard(runtime: store.runtime(for: laravel), project: laravel, style: .tile).frame(width: 260).padding()), CGSize(width: 300, height: 220)),
            ("settings", AnyView(SettingsView()), CGSize(width: 500, height: 520)),
            ("welcome", AnyView(OverviewGrid()), CGSize(width: 700, height: 460)),
        ]
        for (name, view, size) in screens {
            for dark in [false, true] {
                let host = NSHostingView(rootView: view.environmentObject(store).localizedUI()
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
                    .write(to: URL(fileURLWithPath: out).appendingPathComponent("\(lang.rawValue)-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        }
    }
}
