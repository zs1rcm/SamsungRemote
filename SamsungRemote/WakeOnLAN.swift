import Foundation
import Darwin

enum WakeOnLAN {
    enum WakeError: Error, LocalizedError {
        case invalidMAC
        case socketFailed(String)
        case sendFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidMAC:               return "Invalid MAC address"
            case .socketFailed(let m):      return "Socket error: \(m)"
            case .sendFailed(let m):        return "Send failed: \(m)"
            }
        }
    }

    /// Sends a Wake-on-LAN magic packet to the given MAC address. Delivers
    /// to both 255.255.255.255 and the current /24 subnet's broadcast address
    /// (e.g. 192.168.1.255) — the latter is often required because iOS and
    /// many home routers silently drop the all-hosts broadcast.
    @discardableResult
    static func wake(mac: String, port: UInt16 = 9) -> Bool {
        guard let macBytes = parseMAC(mac) else { return false }

        // Magic packet: 6 * 0xFF + MAC repeated 16 times = 102 bytes.
        var packet: [UInt8] = Array(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: macBytes) }

        var targets = ["255.255.255.255"]
        if let ip = LocalNetwork.wifiIPv4Address(),
           let prefix = LocalNetwork.subnet24(of: ip) {
            targets.append("\(prefix).255")
        }

        var anySent = false
        for target in targets {
            if send(packet: packet, to: target, port: port) {
                anySent = true
            }
        }
        return anySent
    }

    // MARK: - Internals

    private static func send(packet: [UInt8], to host: String, port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var broadcast: Int32 = 1
        _ = setsockopt(
            sock, SOL_SOCKET, SO_BROADCAST,
            &broadcast, socklen_t(MemoryLayout<Int32>.size)
        )

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        guard addr.sin_addr.s_addr != INADDR_NONE else { return false }

        let sent = withUnsafePointer(to: &addr) { pointer -> ssize_t in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                packet.withUnsafeBufferPointer { buf in
                    sendto(
                        sock, buf.baseAddress, buf.count, 0,
                        addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        return sent == packet.count
    }

    /// Accepts "AA:BB:CC:DD:EE:FF", "AA-BB-CC-DD-EE-FF", or "AABBCCDDEEFF".
    private static func parseMAC(_ mac: String) -> [UInt8]? {
        let hex = mac.uppercased().filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
