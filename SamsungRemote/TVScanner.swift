import Foundation

/// Discovers Samsung Tizen TVs on the local /24 subnet by concurrent HTTP probes
/// of `http://<host>:8001/api/v2/`. The response contains the MAC address we
/// use as a stable ID across DHCP lease changes.
enum TVScanner {
    struct Result: Identifiable, Equatable, Hashable, Codable {
        var id: String
        var name: String
        var modelName: String?
        var host: String
    }

    /// Quick reachability probe. Returns true iff the host answers the Samsung
    /// device-info endpoint within the timeout.
    static func isReachable(host: String, timeout: TimeInterval = 1.5) async -> Bool {
        await probe(host: host, timeout: timeout) != nil
    }

    /// Full /24 scan based on the current Wi-Fi interface.
    static func scanSubnet(timeout: TimeInterval = 1.5) async -> [Result] {
        guard
            let ipv4 = LocalNetwork.wifiIPv4Address(),
            let prefix = LocalNetwork.subnet24(of: ipv4)
        else {
            return []
        }

        let candidates = (1...254).map { "\(prefix).\($0)" }

        let results = await withTaskGroup(of: Result?.self) { group in
            for host in candidates {
                group.addTask { await probe(host: host, timeout: timeout) }
            }
            var found: [Result] = []
            for await value in group {
                if let value { found.append(value) }
            }
            return found
        }

        // Deduplicate by id, sort by display name.
        var seen = Set<String>()
        let unique = results.filter { seen.insert($0.id).inserted }
        return unique.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func probe(host: String, timeout: TimeInterval = 1.5) async -> Result? {
        guard let url = URL(string: "http://\(host):8001/api/v2/") else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        config.httpShouldUsePipelining = true
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let device = json["device"] as? [String: Any]
        let type = (device?["type"] as? String) ?? ""
        let modelName = device?["modelName"] as? String
        let mac = device?["wifiMac"] as? String
        let udn = json["id"] as? String
        let name = (device?["name"] as? String)
            ?? (json["name"] as? String)
            ?? modelName
            ?? host

        let looksLikeSamsung =
            type.lowercased().contains("samsung")
            || modelName != nil
            || mac != nil

        guard looksLikeSamsung else { return nil }

        let id = (mac?.isEmpty == false ? mac! : (udn?.isEmpty == false ? udn! : host))
        return Result(id: id, name: name, modelName: modelName, host: host)
    }
}

/// Observable wrapper for SwiftUI.
@MainActor
final class TVDiscovery: ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var results: [TVScanner.Result] = []
    @Published private(set) var lastError: String?

    func scan() async {
        isScanning = true
        lastError = nil
        defer { isScanning = false }

        if LocalNetwork.wifiIPv4Address() == nil {
            lastError = "No Wi-Fi connection — join the same network as the TV."
            results = []
            return
        }

        results = await TVScanner.scanSubnet()
        if results.isEmpty {
            lastError = "No Samsung TVs responded on this network."
        }
    }
}
