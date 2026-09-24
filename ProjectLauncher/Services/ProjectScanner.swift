import Foundation

enum ProjectScanner {
    /// How deep below the root to look. A folder that is itself a project is not descended into.
    static let maxDepth = 5
    static let skipped: Set<String> = [
        "node_modules", "vendor", "build", "dist", "Pods", "DerivedData",
        "venv", "__pycache__", "storage", "Library",
    ]

    static func scan(root: URL, fileManager: FileManager = .default) -> [Project] {
        var found: [Project] = []
        let rootPath = root.standardizedFileURL.path

        func visit(_ dir: URL, depth: Int) {
            if let type = ProjectType.detect(in: dir, fileManager: fileManager) {
                var relative = String(dir.standardizedFileURL.path.dropFirst(rootPath.count))
                if relative.hasPrefix("/") { relative.removeFirst() }
                found.append(Project(url: dir, detectedType: type, relativePath: relative.isEmpty ? "." : relative))
                return
            }
            guard depth < maxDepth,
                  let children = try? fileManager.contentsOfDirectory(
                      at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                      options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { return }
            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                guard values?.isDirectory == true, values?.isPackage != true,
                      !skipped.contains(child.lastPathComponent) else { continue }
                visit(child, depth: depth + 1)
            }
        }

        visit(root, depth: 0)
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
