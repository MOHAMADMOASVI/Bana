import Foundation

struct LogLine: Identifiable {
    enum Stream { case stdout, stderr, system }
    let id: Int
    let text: String
    let stream: Stream
    /// Persian/Arabic script breaks apart in a monospaced font; such lines use the proportional one.
    let hasRTLScript: Bool

    init(id: Int, text: String, stream: Stream) {
        self.id = id
        self.text = text
        self.stream = stream
        hasRTLScript = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }

    var looksLikeError: Bool {
        text.range(of: #"\b(error|exception|fatal|traceback|failed)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// Live state of one project's server process. One instance per project, owned by ProjectStore.
@MainActor
final class ProjectRuntime: ObservableObject {
    @Published private(set) var status: RunStatus = .stopped
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var port: Int?
    @Published private(set) var commandLine = ""

    static let maxLogLines = 5000

    private var process: Process?
    private var userStopped = false
    private var stopCompletions: [() -> Void] = []
    private var nextLineID = 0
    private var readinessTask: Task<Void, Never>?

    var isProcessRunning: Bool { process?.isRunning == true }

    func start(spec: LaunchSpec, in directory: URL, searchPath: [String]) {
        guard !status.isActive else { return }
        guard let executable = ExecutableLocator.find(spec.program, in: searchPath) else {
            append(tr("«\(spec.program)» پیدا نشد. این مسیرها جست‌وجو شد:\n  ", "“\(spec.program)” was not found on PATH:\n  ") + searchPath.joined(separator: "\n  "), .system)
            status = .failed(tr("\(spec.program) پیدا نشد", "\(spec.program) not found"))
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = spec.arguments
        process.currentDirectoryURL = directory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath.joined(separator: ":")
        env["FORCE_COLOR"] = "0"
        env["PYTHONUNBUFFERED"] = "1"
        env["TMPDIR"] = Sandbox.tempDirectory
        env.merge(spec.environment) { _, new in new }
        process.environment = env

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        attach(out, as: .stdout)
        attach(err, as: .stderr)

        process.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor in self?.didTerminate(code: code, reason: reason) }
        }

        userStopped = false
        port = spec.port
        commandLine = spec.displayCommand
        append("$ \(executable.path) \(spec.arguments.joined(separator: " "))", .system)
        append("  ↳ \(directory.path)", .system)

        do {
            try process.run()
        } catch {
            append(tr("اجرا نشد: ", "Failed to launch: ") + error.localizedDescription, .system)
            status = .failed(error.localizedDescription)
            return
        }
        self.process = process
        status = .starting
        waitUntilReady()
    }

    /// SIGTERM the whole process tree; SIGKILL whatever is left after `grace` seconds.
    func stop(grace: TimeInterval = 4, then completion: (() -> Void)? = nil) {
        guard let process, process.isRunning else {
            completion?()
            return
        }
        if let completion { stopCompletions.append(completion) }
        guard status != .stopping else { return }
        userStopped = true
        status = .stopping
        append(tr("در حال توقف…", "Stopping…"), .system)

        let pid = process.processIdentifier
        let tree = ProcessTree.descendants(of: pid)
        process.terminate()
        ProcessTree.signal(tree, SIGTERM)

        DispatchQueue.main.asyncAfter(deadline: .now() + grace) { [weak self] in
            let leftovers = (tree + ProcessTree.descendants(of: pid)).filter(ProcessTree.isAlive)
            ProcessTree.signal(leftovers, SIGKILL)
            if process.isRunning {
                kill(pid, SIGKILL)
                Task { @MainActor in self?.append(tr("بعد از \(Int(grace)) ثانیه به‌زور بسته شد.", "Force killed after \(Int(grace))s."), .system) }
            }
        }
    }

    func clearLog() { log.removeAll() }

    /// A start that never got as far as launching (port taken, no free port).
    func fail(_ message: String) {
        append(message, .system)
        status = .failed(message)
    }

    // MARK: - Private

    private func waitUntilReady() {
        readinessTask?.cancel()
        guard let port else {
            status = .running
            return
        }
        readinessTask = Task { [weak self] in
            for _ in 0..<600 { // up to ~5 min (first `npm install`/docker pull can be slow)
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled, self.status == .starting else { return }
                let listening = await Task.detached { PortFinder.isListening(port) }.value
                if listening, self.status == .starting {
                    self.status = .running
                    self.append(tr("روی پورت \(port) آماده است.", "Listening on port \(port)."), .system)
                    return
                }
            }
        }
    }

    private func didTerminate(code: Int32, reason: Process.TerminationReason) {
        readinessTask?.cancel()
        process = nil
        if userStopped || code == 0 {
            append(tr("فرایند بسته شد (\(code)).", "Process exited (\(code))."), .system)
            status = .stopped
        } else {
            let why = reason == .uncaughtSignal ? tr("با سیگنال \(code) بسته شد", "killed by signal \(code)") : tr("با کد \(code) متوقف شد", "exited with code \(code)")
            append(tr("فرایند \(why).", "Process \(why)."), .system)
            status = .failed(why)
        }
        let completions = stopCompletions
        stopCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func attach(_ pipe: Pipe, as stream: LogLine.Stream) {
        let splitter = LineSplitter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            let lines: [String]
            if data.isEmpty {
                handle.readabilityHandler = nil
                lines = splitter.flush()
            } else {
                lines = splitter.feed(data)
            }
            guard !lines.isEmpty else { return }
            Task { @MainActor in self?.append(lines, stream) }
        }
    }

    private func append(_ text: String, _ stream: LogLine.Stream) {
        append(text.components(separatedBy: "\n"), stream)
    }

    private func append(_ lines: [String], _ stream: LogLine.Stream) {
        var batch: [LogLine] = []
        batch.reserveCapacity(lines.count)
        for line in lines {
            batch.append(LogLine(id: nextLineID, text: line, stream: stream))
            nextLineID += 1
        }
        log.append(contentsOf: batch)
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
    }
}

/// Turns a byte stream into clean lines: UTF‑8 safe across chunk boundaries, ANSI codes and \r progress bars removed.
final class LineSplitter: @unchecked Sendable {
    private var pending = Data()
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}(?:\\[[0-?]*[ -/]*[@-~]|\\][^\u{07}]*\u{07}|[@-Z\\\\-_])")

    func feed(_ data: Data) -> [String] {
        pending.append(data)
        guard let lastNewline = pending.lastIndex(of: 0x0A) else { return [] }
        let complete = pending[pending.startIndex...lastNewline]
        pending = Data(pending[pending.index(after: lastNewline)...])
        let text = String(decoding: complete, as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(Self.clean)
    }

    func flush() -> [String] {
        defer { pending.removeAll() }
        guard !pending.isEmpty else { return [] }
        return [Self.clean(Substring(String(decoding: pending, as: UTF8.self)))]
    }

    static func clean(_ raw: Substring) -> String {
        var line = String(raw)
        if let cr = line.lastIndex(of: "\r") {
            let after = line[line.index(after: cr)...]
            line = after.isEmpty ? String(line[..<cr]) : String(after)
        }
        return ansi.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
    }
}
