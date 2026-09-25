import CryptoKit
import Foundation

/// A .env file as editable lines; comments, blank lines and order survive a round trip.
struct EnvDocument: Equatable {
    struct Line: Identifiable, Equatable {
        let id = UUID()
        var key: String      // empty for comments / blank lines
        var value: String    // raw, quotes included
        var raw: String      // used when key is empty

        var isEntry: Bool { !key.isEmpty }

        /// Values worth hiding on screen.
        var isSecret: Bool {
            let k = key.uppercased()
            return ["PASSWORD", "SECRET", "TOKEN", "_KEY", "PASS"].contains { k.contains($0) } || k == "APP_KEY"
        }

        static func == (a: Line, b: Line) -> Bool { a.key == b.key && a.value == b.value && a.raw == b.raw }
    }

    var lines: [Line]

    init(text: String) {
        lines = text.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = line.firstIndex(of: "=") else {
                return Line(key: "", value: "", raw: line)
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return Line(key: "", value: "", raw: line) }
            return Line(key: key, value: String(line[line.index(after: eq)...]), raw: "")
        }
        // A trailing newline shows up as one empty line; keep it out of the editor.
        if lines.count > 1, let last = lines.last, !last.isEntry, last.raw.isEmpty { lines.removeLast() }
    }

    var text: String {
        lines.map { $0.isEntry ? "\($0.key)=\($0.value)" : $0.raw }.joined(separator: "\n") + "\n"
    }

    func value(_ key: String) -> String? { lines.first { $0.key == key }?.value }

    mutating func set(_ key: String, _ value: String) {
        if let i = lines.firstIndex(where: { $0.key == key }) { lines[i].value = value }
        else { lines.append(Line(key: key, value: value, raw: "")) }
    }
}

/// The .env files a project has: `.env*` in its root and under `deploy/`.
enum EnvFiles {
    static func find(in dir: URL) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        func add(from folder: URL) {
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(".env") {
                var isDir: ObjCBool = false
                let url = folder.appendingPathComponent(name)
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue { found.append(url) }
            }
        }
        add(from: dir)
        let deploy = dir.appendingPathComponent("deploy")
        add(from: deploy)
        for sub in (try? fm.contentsOfDirectory(atPath: deploy.path)) ?? [] {
            add(from: deploy.appendingPathComponent(sub))
        }
        // .env first, then the rest alphabetically.
        return found.sorted {
            let a = $0.path.replacingOccurrences(of: dir.path, with: ""), b = $1.path.replacingOccurrences(of: dir.path, with: "")
            if a == "/.env" { return true }
            if b == "/.env" { return false }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    static func write(_ text: String, to url: URL) throws {
        let existing = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        try text.write(to: url, atomically: true, encoding: .utf8)
        // Keep the file's permissions (atomic write would reset them); new files are owner-only.
        try FileManager.default.setAttributes([.posixPermissions: existing ?? 0o600], ofItemAtPath: url.path)
    }
}

/// The user's own .env for a project's hosting package, kept in Application Support (owner-only).
enum HostingEnvStore {
    static func url(for project: Project) -> URL {
        let digest = SHA256.hash(data: Data(project.id.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let dir = SettingsStore.fileURL.deletingLastPathComponent().appendingPathComponent("hosting-env", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("\(digest).env")
    }

    static func load(for project: Project) -> String? { try? String(contentsOf: url(for: project), encoding: .utf8) }

    static func save(_ text: String, for project: Project) throws { try EnvFiles.write(text, to: url(for: project)) }

    static func delete(for project: Project) { try? FileManager.default.removeItem(at: url(for: project)) }
}
