import Foundation

final class AppSettings: ObservableObject {
    private enum Keys {
        static let host = "tvHost"
        static let useTLS = "useTLS"
        static let token = "tvToken"
        static let deviceName = "deviceName"
    }

    @Published var tvHost: String {
        didSet { UserDefaults.standard.set(tvHost, forKey: Keys.host) }
    }

    @Published var useTLS: Bool {
        didSet { UserDefaults.standard.set(useTLS, forKey: Keys.useTLS) }
    }

    @Published var token: String? {
        didSet {
            if let token { UserDefaults.standard.set(token, forKey: Keys.token) }
            else { UserDefaults.standard.removeObject(forKey: Keys.token) }
        }
    }

    @Published var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: Keys.deviceName) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.tvHost = defaults.string(forKey: Keys.host) ?? ""
        self.useTLS = defaults.object(forKey: Keys.useTLS) as? Bool ?? true
        self.token = defaults.string(forKey: Keys.token)
        self.deviceName = defaults.string(forKey: Keys.deviceName) ?? "iPhone Remote"
    }

    var port: Int { useTLS ? 8002 : 8001 }
    var scheme: String { useTLS ? "wss" : "ws" }

    func forgetPairing() { token = nil }
}
