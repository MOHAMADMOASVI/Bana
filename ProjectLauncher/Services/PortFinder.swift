import Foundation

enum PortFinder {
    /// True when nothing is bound to `port` on any IPv4/IPv6 address.
    static func isFree(_ port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }
        return canBind(port, ipv4: INADDR_ANY) && canBind(port, ipv4: INADDR_LOOPBACK) && canBindIPv6(port)
    }

    /// First free port at or after `preferred`, skipping ones we already handed out.
    static func findFree(startingAt preferred: Int, excluding reserved: Set<Int> = [], attempts: Int = 200) -> Int? {
        var port = max(preferred, 1024)
        for _ in 0..<attempts {
            if port > 65535 { port = 1024 }
            if !reserved.contains(port), isFree(port) { return port }
            port += 1
        }
        return nil
    }

    /// Something accepts TCP connections on localhost:port (the server is up).
    static func isListening(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func canBind(_ port: Int, ipv4 host: in_addr_t) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        // SO_REUSEADDR ignores TIME_WAIT leftovers but still fails on a live listener.
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = host.bigEndian
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func canBindIPv6(_ port: Int) -> Bool {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return true } // no IPv6 stack: nothing can be listening there
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = in_port_t(UInt16(port)).bigEndian
        addr.sin6_addr = in6addr_any
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
    }
}
