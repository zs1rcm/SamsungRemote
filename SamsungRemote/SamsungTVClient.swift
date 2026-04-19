import Foundation

@MainActor
final class SamsungTVClient: NSObject, ObservableObject {
    enum Status: Equatable {
        case disconnected
        case resolving
        case connecting
        case awaitingPairing
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .disconnected:     return "Disconnected"
            case .resolving:        return "Finding TV on network…"
            case .connecting:       return "Connecting…"
            case .awaitingPairing:  return "Waiting for TV pairing…"
            case .connected:        return "Connected"
            case .failed(let msg):  return "Error: \(msg)"
            }
        }
    }

    @Published private(set) var status: Status = .disconnected

    private let settings: AppSettings
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var connectTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - Connection

    func connect() {
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            await self?.connectAsync()
        }
    }

    private func connectAsync() async {
        guard let initial = settings.activeTV else {
            status = .failed("No TV selected. Tap Settings → Scan.")
            return
        }

        cancelSocket()

        // 1. Try the stored host. If the TV no longer answers there (common on
        //    DHCP networks), fall back to a subnet scan and match by MAC/UDN.
        var tv = initial
        if !(await TVScanner.isReachable(host: tv.host)) {
            status = .resolving
            let matches = await TVScanner.scanSubnet()
            if let match = matches.first(where: { $0.id == tv.id }) {
                tv.host = match.host
                if let modelName = match.modelName { tv.modelName = modelName }
                settings.update(id: tv.id) {
                    $0.host = match.host
                    if let modelName = match.modelName { $0.modelName = modelName }
                }
            } else {
                status = .failed("TV not found on this network.")
                return
            }
        }

        guard let url = buildURL(for: tv) else {
            status = .failed("Invalid TV URL")
            return
        }

        status = (tv.token == nil) ? .awaitingPairing : .connecting

        let ws = session.webSocketTask(with: url)
        self.task = ws
        ws.resume()
        receiveNext()
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        cancelSocket()
        if case .failed = status { /* preserve error for the user */ }
        else { status = .disconnected }
    }

    private func cancelSocket() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func buildURL(for tv: SavedTV) -> URL? {
        let nameB64 = Data(settings.deviceName.utf8).base64EncodedString()
        var components = URLComponents()
        components.scheme = tv.scheme
        components.host = tv.host
        components.port = tv.port
        components.path = "/api/v2/channels/samsung.remote.control"
        var query = [URLQueryItem(name: "name", value: nameB64)]
        if let token = tv.token, !token.isEmpty {
            query.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = query
        return components.url
    }

    // MARK: - Sending keys

    func send(_ key: TVKey) {
        send(rawKey: key.rawValue)
    }

    func send(rawKey: String) {
        guard let task else {
            status = .failed("Not connected")
            return
        }
        let payload: [String: Any] = [
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": rawKey,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey"
            ]
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let text = String(data: data, encoding: .utf8)
        else { return }

        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Receiving

    private func receiveNext() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.status = .failed(error.localizedDescription)
                case .success(let message):
                    self.handle(message)
                    self.receiveNext()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String? = {
            switch message {
            case .string(let s): return s
            case .data(let d):   return String(data: d, encoding: .utf8)
            @unknown default:    return nil
            }
        }()
        guard
            let text,
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = json["event"] as? String
        else { return }

        switch event {
        case "ms.channel.connect":
            if let payload = json["data"] as? [String: Any],
               let token = payload["token"] as? String,
               !token.isEmpty,
               let id = settings.activeTV?.id {
                settings.update(id: id) { $0.token = token }
            }
            status = .connected

        case "ms.channel.unauthorized":
            if let id = settings.activeTV?.id {
                settings.forgetPairing(id: id)
            }
            status = .failed("Pairing denied on the TV")

        case "ms.channel.timeOut":
            status = .failed("Pairing timed out")

        default:
            break
        }
    }
}

extension SamsungTVClient: URLSessionDelegate {
    // Samsung Tizen TVs present a self-signed cert on port 8002.
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
