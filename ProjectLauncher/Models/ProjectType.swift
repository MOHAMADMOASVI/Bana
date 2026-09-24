import SwiftUI

enum ProjectType: String, Codable, CaseIterable, Identifiable {
    case laravel, php, python, node, docker

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .laravel: "Laravel"
        case .php: "PHP"
        case .python: "Python"
        case .node: "Node.js"
        case .docker: "Docker"
        }
    }

    var symbol: String {
        switch self {
        case .laravel: "flame"
        case .php: "chevron.left.forwardslash.chevron.right"
        case .python: "curlybraces.square"
        case .node: "hexagon"
        case .docker: "shippingbox"
        }
    }

    var tint: Color {
        switch self {
        case .laravel: .red
        case .php: .indigo
        case .python: .blue
        case .node: .green
        case .docker: .cyan
        }
    }

    var defaultPort: Int {
        switch self {
        case .laravel, .php: 8000
        case .python: 8100
        case .node: 5173
        case .docker: 8080
        }
    }

    /// Key files checked in priority order; first match wins.
    static let markers: [(ProjectType, [String])] = [
        (.laravel, ["artisan"]),
        (.php, ["composer.json", "index.php", "public/index.php"]),
        (.python, ["requirements.txt", "main.py"]),
        (.node, ["package.json"]),
        (.docker, ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"]),
    ]

    static func detect(in directory: URL, fileManager: FileManager = .default) -> ProjectType? {
        for (type, files) in markers {
            for file in files where fileManager.fileExists(atPath: directory.appendingPathComponent(file).path) {
                return type
            }
        }
        return nil
    }
}
