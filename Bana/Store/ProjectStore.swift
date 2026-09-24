import AppKit
import Combine
import SwiftUI

@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    @Published private(set) var rootURL: URL?
    @Published private(set) var projects: [Project] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lanIP: String?
    @Published var selection: Project.ID?

    private var settings: AppSettings
    private var runtimes: [Project.ID: ProjectRuntime] = [:]
    private var ipTimer: Timer?
    private var statusWatchers: [AnyCancellable] = []

    init() {
        settings = SettingsStore.load()
        lanIP = NetworkInfo.localIPv4()
        restoreRoot()
        ipTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in ProjectStore.shared.refreshIP() }
        }
    }

    // MARK: Root folder

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = tr("انتخاب", "Choose")
        panel.message = tr("پوشه‌ای را که پروژه‌هایتان در آن است انتخاب کنید", "Choose the folder that contains your projects")
        panel.directoryURL = rootURL ?? URL(fileURLWithPath: ExecutableLocator.realHome + "/Projects")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        rootURL?.stopAccessingSecurityScopedResource()
        settings.rootBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        settings.rootPath = url.path
        persist()
        _ = url.startAccessingSecurityScopedResource()
        rootURL = url
        rescan()
    }

    private func restoreRoot() {
        var stale = false
        guard let url = settings.rootBookmark.flatMap({
            try? URL(resolvingBookmarkData: $0, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        }) ?? settings.rootPath.flatMap({ path in
            // Not sandboxed: a plain path is enough when there is no (valid) bookmark.
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path, isDirectory: true) : nil
        }) else { return }
        _ = url.startAccessingSecurityScopedResource()
        if stale || settings.rootBookmark == nil {
            settings.rootBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            persist()
        }
        rootURL = url
        rescan()
    }

    func rescan() {
        guard let root = rootURL, !isScanning else { return }
        isScanning = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { ProjectScanner.scan(root: root) }.value
            // Keep projects that are still running even if their marker file vanished.
            let running = projects.filter { runtimes[$0.id]?.status.isActive == true && !found.map(\.id).contains($0.id) }
            projects = found + running
            isScanning = false
            if let sel = selection, !projects.contains(where: { $0.id == sel }) { selection = nil }
        }
    }

    func refreshIP() { lanIP = NetworkInfo.localIPv4() }

    // MARK: Per-project state

    func runtime(for project: Project) -> ProjectRuntime {
        if let rt = runtimes[project.id] { return rt }
        let rt = ProjectRuntime()
        runtimes[project.id] = rt
        // Status changes (not every log line) refresh store-level views like the running count.
        statusWatchers.append(rt.$status.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() })
        return rt
    }

    func settings(for project: Project) -> ProjectSettings { settings.projects[project.id] ?? ProjectSettings() }

    func updateSettings(for project: Project, _ change: (inout ProjectSettings) -> Void) {
        var s = settings(for: project)
        change(&s)
        settings.projects[project.id] = s.isEmpty ? nil : s
        persist()
        objectWillChange.send()
    }

    func type(of project: Project) -> ProjectType { settings(for: project).typeOverride ?? project.detectedType }

    func project(withID id: Project.ID?) -> Project? { projects.first { $0.id == id } }

    // MARK: Start / stop

    func start(_ project: Project) {
        let rt = runtime(for: project)
        guard !rt.status.isActive else { return }
        refreshIP()
        let s = settings(for: project)
        let type = type(of: project)
        let reserved = Set(runtimes.values.filter { $0.status.isActive }.compactMap(\.port))

        let port: Int
        if let fixed = s.port {
            guard PortFinder.isFree(fixed), !reserved.contains(fixed) else {
                rt.fail(tr("پورت \(fixed) در حال استفاده است. در تنظیمات پروژه عوضش کنید یا خالی بگذارید تا خودکار انتخاب شود.", "Port \(fixed) is already in use. Change it in the project settings or clear it to pick one automatically."))
                return
            }
            port = fixed
        } else if let free = PortFinder.findFree(startingAt: type.defaultPort, excluding: reserved) {
            port = free
        } else {
            rt.fail(tr("نزدیک پورت \(type.defaultPort) پورت آزادی پیدا نشد.", "No free port found near \(type.defaultPort)."))
            return
        }

        let spec = CommandBuilder.spec(for: project, type: type, port: port, customCommand: s.customCommand)
        rt.start(spec: spec, in: project.url, searchPath: ExecutableLocator.searchPath(for: project.url))
    }

    func stop(_ project: Project) {
        runtimes[project.id]?.stop(grace: type(of: project) == .docker ? 20 : 4)
    }

    func toggle(_ project: Project) {
        runtime(for: project).status.isActive ? stop(project) : start(project)
    }

    /// Local URL for the browser; LAN URL for other devices.
    func url(for project: Project, lan: Bool = false) -> URL? {
        guard let port = runtimes[project.id]?.port else { return nil }
        let host = lan ? (lanIP ?? "127.0.0.1") : "localhost"
        return URL(string: "http://\(host):\(port)")
    }

    func openInBrowser(_ project: Project) {
        if let url = url(for: project) { NSWorkspace.shared.open(url) }
    }

    var runningCount: Int { runtimes.values.filter { $0.isProcessRunning }.count }

    func stopAll(completion: @escaping () -> Void) {
        let active = runtimes.filter { $0.value.isProcessRunning }
        guard !active.isEmpty else { return completion() }
        var remaining = active.count
        for (id, rt) in active {
            let grace: TimeInterval = project(withID: id).map { type(of: $0) == .docker ? 10 : 3 } ?? 3
            rt.stop(grace: grace) {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
    }

    private func persist() { SettingsStore.save(settings) }
}
