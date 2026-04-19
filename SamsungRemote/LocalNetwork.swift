import Foundation
import Darwin

enum LocalNetwork {
    /// IPv4 address of the Wi-Fi interface (en0), e.g. "192.168.1.57".
    static func wifiIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let interface = current.pointee
            guard
                let addr = interface.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr, socklen_t(addr.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            )
            if result == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    /// From "192.168.1.42" returns "192.168.1" — the /24 prefix.
    static func subnet24(of ipv4: String) -> String? {
        let parts = ipv4.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".")
    }
}
