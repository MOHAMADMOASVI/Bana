import Foundation

/// Per-project overrides, persisted as JSON.
struct ProjectSettings: Codable, Equatable {
    var port: Int?
    /// Replaces the default command. `{port}` is substituted; runs without a shell.
    var customCommand: String?
    var typeOverride: ProjectType?

    var isEmpty: Bool { port == nil && (customCommand ?? "").isEmpty && typeOverride == nil }
}

struct AppSettings: Codable {
    var rootBookmark: Data?
    var rootPath: String?
    var projects: [String: ProjectSettings] = [:]
}
