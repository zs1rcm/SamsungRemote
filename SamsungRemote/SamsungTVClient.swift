import Foundation

@MainActor
final class SamsungTVClient: NSObject, ObservableObject {
    enum Status: Equatable {
        case disconnected
        case waking
        case resolving
        case connecting
        case awaitingPairing
        case connected
        case reconnecting
        case failed(String)

        var label: String {
            switch self {
            case .disconnected:     return "Disconnected"
            case .waking:           return "Waking TV…"
            case .resolving:        return "Finding TV on network…"
            case .connecting:       return "Connecting…"
            case .awaitingPairing:  return "Waiting for TV pairing…"
            case .connected:        return "Connected"
            case .reconnecting:     return "Reconnecting…"
            case .failed(let msg):  return "Error: \(msg)"
            }
        }
    }

    @Published private(set) var status: Status = .disconnected

    private let settings: AppSettings
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var connectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    /// Keys queued while the socket is being (re-)established. Flushed once
    /// the TV sends `ms.channel.connect`.
    private var pendingKeys: [String] = []

    private var wantsConnection = false
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5
    private let pingInterval: UInt64 = 20_000_000_000 // 20 s

    /// How long we're willing to wait for a WoL'd TV to come back up before
    /// falling back to the subnet scan (or reporting failure).
    private let wakePollAttempts = 20
    private let wakePollInterval: UInt64 = 1_000_000_000 // 1 s

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - Public API

    func connect() {
        wantsConnection = true
        reconnectAttempt = 0
        startConnect()
    }

    func disconnect() {
        wantsConnection = false
        reconnectAttempt = 0
        pendingKeys.removeAll()
        connectTask?.cancel()
        connectTask = nil
        pingTask?.cancel()
        pingTask = nil
        cancelSocket()
        if case .failed = status { /* keep error visible */ }
        else { status = .disconnected }
    }

    /// Fire-and-forget wake for the active TV. Does not attempt to connect
    /// afterwards.
    @discardableResult
    func wakeActive() -> Bool {
        guard let mac = settings.activeTV?.effectiveMAC else { return false }
        return WakeOnLAN.wake(mac: mac)
    }

    func send(_ key: TVKey) { send(rawKey: key.rawValue) }

    func send(rawKey: String) {
        if status != .connected || task?.state != .running {
            pendingKeys.append(rawKey)
            if !wantsConnection || connectTask == nil {
                connect()
            } else if status == .disconnected {
                startConnect()
            }
            return
        }
        deliver(rawKey: rawKey)
    }

    // MARK: - Connect

    private func startConnect() {
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            await self?.connectAsync()
        }
    }

    private func connectAsync() async {
        guard let initial = settings.activeTV else {
            status = .failed("No TV selected. Tap Settings → Scan.")
            wantsConnection = false
            return
        }

        cancelSocket()
        pingTask?.cancel()

        var tv = initial

        // 1. If the stored host doesn't answer, try Wake-on-LAN (if we know
        //    the MAC) then poll for the TV to appear on the same IP.
        if !(await TVScanner.isReachable(host: tv.host)) {
            if let mac = tv.effectiveMAC {
                status = .waking
                WakeOnLAN.wake(mac: mac)
                if await pollReachable(host: tv.host) {
                    // TV came back up on the same address.
                } else if Task.isCancelled {
                    return
                }
            }
        }

        // 2. Still not reachable → maybe the DHCP lease moved. Rescan and
        //    match by MAC/UDN.
        if !(await TVScanner.isReachable(host: tv.host)) {
            status = .resolving
            let matches = await TVScanner.scanSubnet()
            if let match = matches.first(where: { $0.id == tv.id })
                ?? matches.first(where: { tv.effectiveMAC != nil && $0.mac?.uppercased() == tv.effectiveMAC })
            {
                tv.host = match.host
                if let modelName = match.modelName { tv.modelName = modelName }
                if let mac = match.mac { tv.mac = mac }
                settings.update(id: tv.id) {
                    $0.host = match.host
                    if let modelName = match.modelName { $0.modelName = modelName }
                    if let mac = match.mac { $0.mac = mac }
                }
            } else {
                scheduleReconnectOrFail("TV not reachable. Power it on or check Wi-Fi.")
                return
            }
        }

        guard let url = buildURL(for: tv) else {
            status = .failed("Invalid TV URL")
            return
        }

        if reconnectAttempt > 0 {
            status = .reconnecting
        } else {
            status = (tv.token == nil) ? .awaitingPairing : .connecting
        }

        let ws = session.webSocketTask(with: url)
        self.task = ws
        ws.resume()
        receiveNext()
    }

    /// Polls the given host for reachability up to `wakePollAttempts` times.
    /// Returns true as soon as it answers, false if the poll runs out.
    private func pollReachable(host: String) async -> Bool {
        for _ in 0..<wakePollAttempts {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: wakePollInterval)
            if await TVScanner.isReachable(host: host, timeout: 0.8) {
                return true
            }
        }
        return false
    }

    private func scheduleReconnectOrFail(_ message: String) {
        guard wantsConnection, reconnectAttempt < maxReconnectAttempts else {
            status = .failed(message)
            wantsConnection = false
            return
        }
        reconnectAttempt += 1
        let delayNS = UInt64(pow(2.0, Double(reconnectAttempt - 1)) * 1_000_000_000)
        status = .reconnecting
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNS)
            await self?.connectAsync()
        }
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

    // MARK: - Send

    private func deliver(rawKey: String) {
        guard let task, task.state == .running else {
            pendingKeys.append(rawKey)
            startConnect()
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
                guard let self else { return }
                self.pendingKeys.append(rawKey)
                self.socketDied(reason: error.localizedDescription)
            }
        }
    }

    private func flushPending() {
        let keys = pendingKeys
        pendingKeys.removeAll()
        for key in keys { deliver(rawKey: key) }
    }

    // MARK: - Receive + keepalive

    private func receiveNext() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.socketDied(reason: error.localizedDescription)
                case .success(let message):
                    self.handle(message)
                    self.receiveNext()
                }
            }
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.pingInterval)
                if Task.isCancelled { return }
                await self.sendPing()
            }
        }
    }

    private func sendPing() async {
        guard let task, task.state == .running else { return }
        task.sendPing { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.socketDied(reason: "Keepalive failed: \(error.localizedDescription)")
            }
        }
    }

    private func socketDied(reason: String) {
        cancelSocket()
        pingTask?.cancel()
        if wantsConnection {
            scheduleReconnectOrFail(reason)
        } else {
            status = .disconnected
        }
    }

    // MARK: - TV protocol

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
               let token = extractToken(from: payload),
               let id = settings.activeTV?.id {
                settings.update(id: id) { $0.token = token }
            }
            status = .connected
            reconnectAttempt = 0
            startPingLoop()
            flushPending()

        case "ms.channel.unauthorized":
            if let id = settings.activeTV?.id {
                settings.forgetPairing(id: id)
            }
            wantsConnection = false
            status = .failed("TV refused pairing. Try Connect again to re-pair.")

        case "ms.channel.timeOut":
            status = .failed("Pairing timed out. Try Connect again.")
            wantsConnection = false

        default:
            break
        }
    }

    private func extractToken(from payload: [String: Any]) -> String? {
        let raw = payload["token"]
        var candidate: String?
        if let s = raw as? String {
            candidate = s
        } else if let n = raw as? NSNumber {
            candidate = n.stringValue
        }
        guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value != "0"
        else { return nil }
        return value
    }
}

extension SamsungTVClient: URLSessionDelegate {
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
