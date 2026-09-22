import Foundation

struct SavedTV: Codable, Identifiable, Equatable, Hashable {
    /// Stable identifier — MAC address when available, otherwise UDN or host.
    var id: String
    var name: String
    var modelName: String?
    /// Last known IPv4 address. May become stale across DHCP leases; resolved on connect.
    var host: String
    /// MAC address in colon-hex form (e.g. "AA:BB:CC:DD:EE:FF"). Used for
    /// Wake-on-LAN when the TV is powered off.
    var mac: String?
    var useTLS: Bool
    var token: String?

    var port: Int { useTLS ? 8002 : 8001 }
    var scheme: String { useTLS ? "wss" : "ws" }

    /// Best-effort MAC accessor: if the field is set use it, otherwise infer
    /// from `id` when it looks like a MAC (colon-hex 6 groups). Lets older
    /// saved TVs (from before the `mac` field existed) still support WoL.
    var effectiveMAC: String? {
        if let mac, !mac.isEmpty { return mac }
        let parts = id.split(separator: ":")
        if parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) {
            return id.uppercased()
        }
        return nil
    }

    var displayName: String {
        name.isEmpty ? (modelName ?? host) : name
    }

    var subtitle: String {
        let parts = [modelName, host].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
