import Foundation

struct SavedTV: Codable, Identifiable, Equatable, Hashable {
    /// Stable identifier — MAC address when available, otherwise UDN or host.
    var id: String
    var name: String
    var modelName: String?
    /// Last known IPv4 address. May become stale across DHCP leases; resolved on connect.
    var host: String
    var useTLS: Bool
    var token: String?

    var port: Int { useTLS ? 8002 : 8001 }
    var scheme: String { useTLS ? "wss" : "ws" }

    var displayName: String {
        name.isEmpty ? (modelName ?? host) : name
    }

    var subtitle: String {
        let parts = [modelName, host].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
