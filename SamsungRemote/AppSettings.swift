import Foundation

final class AppSettings: ObservableObject {
    private enum Keys {
        static let tvs = "savedTVs.v1"
        static let activeID = "activeTVID"
        static let deviceName = "deviceName"

        // Legacy single-TV keys (v0 migration)
        static let legacyHost = "tvHost"
        static let legacyTLS = "useTLS"
        static let legacyToken = "tvToken"
    }

    @Published var savedTVs: [SavedTV] {
        didSet { persistTVs() }
    }

    @Published var activeTVID: String? {
        didSet {
            let defaults = UserDefaults.standard
            if let id = activeTVID {
                defaults.set(id, forKey: Keys.activeID)
            } else {
                defaults.removeObject(forKey: Keys.activeID)
            }
        }
    }

    @Published var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: Keys.deviceName) }
    }

    init() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Keys.tvs),
           let list = try? JSONDecoder().decode([SavedTV].self, from: data) {
            self.savedTVs = list
        } else {
            self.savedTVs = []
        }
        self.activeTVID = defaults.string(forKey: Keys.activeID)
        self.deviceName = defaults.string(forKey: Keys.deviceName) ?? "iPhone Remote"

        // One-shot migration from the v0 single-TV settings.
        if savedTVs.isEmpty,
           let host = defaults.string(forKey: Keys.legacyHost),
           !host.isEmpty {
            let tls = defaults.object(forKey: Keys.legacyTLS) as? Bool ?? true
            let token = defaults.string(forKey: Keys.legacyToken)
            let tv = SavedTV(
                id: host,
                name: host,
                modelName: nil,
                host: host,
                useTLS: tls,
                token: token
            )
            savedTVs = [tv]
            activeTVID = tv.id
            defaults.removeObject(forKey: Keys.legacyHost)
            defaults.removeObject(forKey: Keys.legacyTLS)
            defaults.removeObject(forKey: Keys.legacyToken)
        }
    }

    // MARK: - Active TV

    var activeTV: SavedTV? {
        guard let id = activeTVID else { return savedTVs.first }
        return savedTVs.first { $0.id == id } ?? savedTVs.first
    }

    func setActive(_ id: String) {
        activeTVID = id
    }

    // MARK: - Mutations

    /// Insert or update a TV by id. Existing tokens are preserved unless
    /// explicitly overwritten in the incoming value.
    @discardableResult
    func upsert(_ tv: SavedTV, makeActive: Bool = false) -> SavedTV {
        var merged = tv
        if let existing = savedTVs.first(where: { $0.id == tv.id }) {
            if merged.token == nil { merged.token = existing.token }
            if merged.modelName == nil { merged.modelName = existing.modelName }
        }
        if let idx = savedTVs.firstIndex(where: { $0.id == tv.id }) {
            savedTVs[idx] = merged
        } else {
            savedTVs.append(merged)
        }
        if makeActive || activeTVID == nil {
            activeTVID = merged.id
        }
        return merged
    }

    func remove(id: String) {
        savedTVs.removeAll { $0.id == id }
        if activeTVID == id {
            activeTVID = savedTVs.first?.id
        }
    }

    /// Mutates a TV in place by id.
    func update(id: String, _ mutate: (inout SavedTV) -> Void) {
        guard let idx = savedTVs.firstIndex(where: { $0.id == id }) else { return }
        var tv = savedTVs[idx]
        mutate(&tv)
        savedTVs[idx] = tv
    }

    func forgetPairing(id: String) {
        update(id: id) { $0.token = nil }
    }

    // MARK: - Persistence

    private func persistTVs() {
        if let data = try? JSONEncoder().encode(savedTVs) {
            UserDefaults.standard.set(data, forKey: Keys.tvs)
        }
    }
}
