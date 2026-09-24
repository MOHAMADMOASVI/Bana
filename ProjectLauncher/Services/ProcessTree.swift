import Darwin

/// `npm run dev` / `docker compose` spawn children that outlive a plain terminate(); we signal the whole tree.
enum ProcessTree {
    static func descendants(of pid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var queue = [pid]
        while let parent = queue.popLast() {
            let children = childPIDs(of: parent)
            result += children
            queue += children
        }
        return result
    }

    static func signal(_ pids: [pid_t], _ sig: Int32) {
        for pid in pids where pid > 0 { kill(pid, sig) }
    }

    static func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    private static func childPIDs(of pid: pid_t) -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), nil, 0)
        guard bytes > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 8)
        let filled = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return buffer.prefix(Int(filled) / MemoryLayout<pid_t>.size).filter { $0 > 0 }
    }
}
