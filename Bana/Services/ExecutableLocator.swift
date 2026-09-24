import Foundation

/// Apps launched from Finder get a minimal PATH, so we build one from the usual install locations.
enum ExecutableLocator {
    /// The real home directory (inside the sandbox `NSHomeDirectory()` is the container).
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    static func searchPath(for projectDir: URL) -> [String] {
        let home = realHome
        let fm = FileManager.default
        var dirs = [
            projectDir.appendingPathComponent(".venv/bin").path,
            projectDir.appendingPathComponent("venv/bin").path,
            projectDir.appendingPathComponent("node_modules/.bin").path,
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "\(home)/.local/bin", "\(home)/.pyenv/shims", "\(home)/.volta/bin",
            "\(home)/.bun/bin", "\(home)/Library/Application Support/Herd/bin",
            "/Applications/Docker.app/Contents/Resources/bin",
        ]
        // Newest nvm node and python.org framework installs.
        for base in ["\(home)/.nvm/versions/node", "/Library/Frameworks/Python.framework/Versions"] {
            let versions = (try? fm.contentsOfDirectory(atPath: base))?
                .filter { !$0.hasPrefix(".") && $0 != "Current" }
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending } ?? []
            if let latest = versions.first { dirs.append("\(base)/\(latest)/bin") }
        }
        dirs += ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return dirs
    }

    static func find(_ name: String, in path: [String]) -> URL? {
        if name.contains("/") {
            let expanded = name.hasPrefix("~/") ? realHome + name.dropFirst() : name
            return FileManager.default.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        for dir in path {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }
}
