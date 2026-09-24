import Foundation

struct LaunchSpec: Equatable {
    var program: String          // name looked up on PATH, or a path
    var arguments: [String]
    var environment: [String: String] = [:]
    /// nil → no HTTP URL to open (e.g. a compose file without published ports).
    var port: Int?

    var displayCommand: String {
        ([program] + arguments).map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }
}

enum Sandbox {
    static var isActive: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }
    /// Writable temp dir: inside the container when sandboxed.
    static var tempDirectory: String { (NSTemporaryDirectory() as NSString).standardizingPath }
}

enum CommandBuilder {
    static func spec(for project: Project, type: ProjectType, port: Int, customCommand: String?) -> LaunchSpec {
        let env = ["PORT": String(port), "HOST": "0.0.0.0"]
        if let custom = customCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let tokens = tokenize(custom.replacingOccurrences(of: "{port}", with: String(port)))
            if let program = tokens.first {
                return LaunchSpec(program: program, arguments: Array(tokens.dropFirst()), environment: env, port: port)
            }
        }
        let dir = project.url
        let fm = FileManager.default
        switch type {
        case .laravel:
            // artisan serve keeps Laravel's own router and env handling; it spawns php -S as a child.
            return LaunchSpec(program: "php",
                              arguments: ["artisan", "serve", "--host=0.0.0.0", "--port=\(port)", "--no-reload", "--tries=1"],
                              environment: env, port: port)

        case .php:
            var args = ["-S", "0.0.0.0:\(port)"]
            // Sandboxed children can't write /tmp; opcache refuses to start without its lock file.
            if Sandbox.isActive { args = ["-d", "opcache.lockfile_path=\(Sandbox.tempDirectory)"] + args }
            // Laravel / Symfony style front controller.
            if fm.fileExists(atPath: dir.appendingPathComponent("public/index.php").path) { args += ["-t", "public"] }
            return LaunchSpec(program: "php", arguments: args, environment: env, port: port)

        case .python:
            let hasRoot = fm.fileExists(atPath: dir.appendingPathComponent("main.py").path)
            let hasApp = fm.fileExists(atPath: dir.appendingPathComponent("app/main.py").path)
            let entry = hasRoot || !hasApp ? "main.py" : "app/main.py"
            let source = (try? String(contentsOf: dir.appendingPathComponent(entry), encoding: .utf8)) ?? ""
            let module = entry == "main.py" ? "main" : "app.main"
            if source.contains("FastAPI(") || source.contains("Starlette(") || source.isEmpty {
                return LaunchSpec(program: "uvicorn",
                                  arguments: ["\(module):app", "--host", "0.0.0.0", "--port", String(port)],
                                  environment: env, port: port)
            }
            if source.contains("Flask(") {
                return LaunchSpec(program: "flask",
                                  arguments: ["--app", module, "run", "--host", "0.0.0.0", "--port", String(port)],
                                  environment: env, port: port)
            }
            // A script or desktop app, not a web server: run it, no URL.
            return LaunchSpec(program: "python3", arguments: ["-u", entry], environment: env, port: nil)

        case .node:
            let scripts = packageScripts(in: dir)
            let script = scripts["dev"] != nil || scripts.isEmpty ? "dev" : (scripts["start"] != nil ? "start" : "dev")
            var args = script == "dev" ? ["run", "dev"] : ["start"]
            let body = scripts[script] ?? ""
            // Most dev servers ignore $PORT/$HOST; pass flags for the common ones.
            if body.contains("vite") || body.contains("astro") || body.contains("nuxt") {
                args += ["--", "--host", "0.0.0.0", "--port", String(port)]
            } else if body.contains("next") {
                args += ["--", "-H", "0.0.0.0", "-p", String(port)]
            }
            return LaunchSpec(program: "npm", arguments: args, environment: env, port: port)

        case .docker:
            return LaunchSpec(program: "docker", arguments: ["compose", "up"], environment: [:],
                              port: composePublishedPort(in: dir))
        }
    }

    static func packageScripts(in dir: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json["scripts"] as? [String: String] ?? [:]
    }

    /// First host port from a `"8080:80"` style mapping.
    static func composePublishedPort(in dir: URL) -> Int? {
        for file in ["docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"] {
            guard let text = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else { continue }
            let regex = try! NSRegularExpression(pattern: #"-\s*["']?(?:[\d.]+:)?(\d{2,5}):\d{1,5}"#)
            if let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(m.range(at: 1), in: text) { return Int(text[r]) }
        }
        return nil
    }

    /// Splits like a shell would for plain words and quotes — no expansion, no pipes.
    static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        var escaped = false
        for ch in command {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" && quote != "'" { escaped = true; hasToken = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch; hasToken = true
            } else if ch.isWhitespace {
                if hasToken { tokens.append(current); current = ""; hasToken = false }
            } else {
                current.append(ch); hasToken = true
            }
        }
        if hasToken { tokens.append(current) }
        return tokens
    }
}
