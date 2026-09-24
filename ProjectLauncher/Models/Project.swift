import Foundation

struct Project: Identifiable, Hashable {
    /// Absolute path; stable identity across rescans and the key for saved settings.
    var id: String { url.path }
    let url: URL
    let detectedType: ProjectType
    /// Path relative to the scanned root, for display ("clients/acme").
    let relativePath: String

    var name: String { url.lastPathComponent }
}
