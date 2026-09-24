import Foundation

enum NetworkInfo {
    /// The Mac's LAN IPv4 address, preferring Wi‑Fi/Ethernet (en*) over VPN/bridge interfaces.
    static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard !ip.hasPrefix("169.254.") else { continue }
            candidates.append((String(cString: ifa.ifa_name), ip))
        }

        func rank(_ name: String) -> Int {
            if name.hasPrefix("en") { return 0 }
            if name.hasPrefix("bridge") || name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("llw") { return 2 }
            return 1
        }
        return candidates.min { (rank($0.name), $0.name) < (rank($1.name), $1.name) }?.ip
    }
}
