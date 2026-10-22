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

    /// After a wake, how long we're willing to wait for the TV to report
    /// `PowerState == "on"` before opening the socket, and the grace period
    /// we add on top so the remote-control service has loaded its paired
    /// device list. Connecting mid-boot is the usual reason a perfectly good
    /// token gets answered with `ms.channel.unauthorized`.
    private let bootPollAttempts = 20
    private let bootGraceNS: UInt64 = 3_000_000_000 // 3 s

    /// Consecutive `ms.channel.unauthorized` replies received while we still
    /// hold a token. The token is only discarded (forcing a new Allow prompt
    /// on the TV) once this reaches `maxUnauthorizedRetriesWithToken`.
    private var unauthorizedWithTokenCount = 0
    private let maxUnauthorizedRetriesWithToken = 3

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
        unauthorizedWithTokenCount = 0
        startConnect()
    }

    func disconnect() {
        wantsConnection = false
        reconnectAttempt = 0
        unauthorizedWithTokenCount = 0
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

        DiagnosticLog.shared.log(
            "Connect attempt for \(initial.displayName) at \(initial.host):\(initial.port); token=\(initial.token == nil ? "none" : "\(initial.token!.prefix(4))••••"); mac=\(initial.effectiveMAC ?? "unknown")"
        )

        var tv = initial
        var sentWake = false

        if !(await TVScanner.isReachable(host: tv.host)) {
            if let mac = tv.effectiveMAC {
                status = .waking
                DiagnosticLog.shared.log("Host unreachable; sending WoL to \(mac)")
                WakeOnLAN.wake(mac: mac)
                sentWake = true
                if await pollReachable(host: tv.host) {
                    DiagnosticLog.shared.log("TV woke on same IP")
                } else if Task.isCancelled {
                    return
                }
            }
        }

        if !(await TVScanner.isReachable(host: tv.host)) {
            status = .resolving
            DiagnosticLog.shared.log("Rescanning subnet to find TV by MAC")
            let matches = await TVScanner.scanSubnet()
            if let match = matches.first(where: { $0.id == tv.id })
                ?? matches.first(where: { tv.effectiveMAC != nil && $0.mac?.uppercased() == tv.effectiveMAC })
            {
                DiagnosticLog.shared.log("Found TV at \(match.host) (was \(tv.host))")
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

        if sentWake {
            status = .waking
            await waitForBootToSettle(host: tv.host)
            if Task.isCancelled { return }
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

    /// The device-info endpoint comes up well before the remote-control
    /// service has finished loading its paired-device list. If we open the
    /// socket in that window the TV answers our valid token with
    /// `ms.channel.unauthorized`. Wait for `PowerState == "on"` (firmwares
    /// that report it) and then a short grace period.
    private func waitForBootToSettle(host: String) async {
        for attempt in 0..<bootPollAttempts {
            if Task.isCancelled { return }
            // A failed probe means the TV is momentarily unreachable — keep
            // waiting. A probe without a PowerState field means this firmware
            // doesn't report it, so the grace period alone has to do.
            guard let info = await TVScanner.probe(host: host, timeout: 0.8) else {
                try? await Task.sleep(nanoseconds: wakePollInterval)
                continue
            }
            let state = info.powerState
            if state == nil || state?.lowercased() == "on" {
                DiagnosticLog.shared.log(
                    "TV reports PowerState=\(state ?? "n/a") after \(attempt + 1) poll(s); settling \(bootGraceNS / 1_000_000_000) s before connecting"
                )
                break
            }
            try? await Task.sleep(nanoseconds: wakePollInterval)
        }
        try? await Task.sleep(nanoseconds: bootGraceNS)
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
        let url = components.url
        if let url {
            let redacted = url.absoluteString
                .replacingOccurrences(of: (tv.token ?? ""), with: "•••")
            DiagnosticLog.shared.log("URL: \(redacted) (name=\(settings.deviceName))")
        }
        return url
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

        task.send(.string(text)) { [weak self, weak task] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, self.isCurrent(task) else { return }
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
        guard let ws = task else { return }
        ws.receive { [weak self, weak ws] result in
            Task { @MainActor in
                // A socket we've already discarded (after an unauthorized
                // reply, a reconnect, or Disconnect) still completes its
                // pending receive, usually with a "cancelled" error. Acting
                // on that would trigger a second reconnect on top of the one
                // already scheduled and overwrite the status we just set.
                guard let self, self.isCurrent(ws) else { return }
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
        task.sendPing { [weak self, weak task] error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, self.isCurrent(task) else { return }
                self.socketDied(reason: "Keepalive failed: \(error.localizedDescription)")
            }
        }
    }

    /// True iff `candidate` is the socket we are currently using. Callbacks
    /// from any other socket are stale and must be ignored.
    private func isCurrent(_ candidate: URLSessionWebSocketTask?) -> Bool {
        guard let candidate, let task else { return false }
        return candidate === task
    }

    private func socketDied(reason: String) {
        DiagnosticLog.shared.log("Socket died: \(reason)", level: .warn)
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
        guard let text else { return }
        DiagnosticLog.shared.log("← \(text.prefix(400))", level: .event)

        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = json["event"] as? String
        else { return }

        // Some firmwares embed the payload as a JSON-encoded string rather
        // than a nested object. Normalise both shapes into a dict.
        let payload = normalisedData(from: json["data"])

        // Try to capture a token from ANY event, not just ms.channel.connect,
        // because certain Samsungs deliver it in ms.channel.registered or
        // similar.
        if let payload, let token = extractToken(from: payload) {
            if let activeID = settings.activeTV?.id {
                let previous = settings.activeTV?.token
                settings.update(id: activeID) { $0.token = token }
                UserDefaults.standard.synchronize()
                if previous != token {
                    DiagnosticLog.shared.log("Token saved for \(activeID.prefix(20)): \(token.prefix(4))••••")
                } else {
                    DiagnosticLog.shared.log("Token re-confirmed (unchanged)")
                }
            } else {
                DiagnosticLog.shared.log("Got token but no active TV to save it against", level: .warn)
            }
        }

        switch event {
        case "ms.channel.connect":
            status = .connected
            reconnectAttempt = 0
            unauthorizedWithTokenCount = 0
            startPingLoop()
            flushPending()
            DiagnosticLog.shared.log("Connected. Pending keys queued: \(pendingKeys.count)")

        case "ms.channel.unauthorized":
            handleUnauthorized()

        case "ms.channel.timeOut":
            status = .failed("Pairing timed out. Try Connect again.")
            wantsConnection = false
            DiagnosticLog.shared.log("ms.channel.timeOut", level: .warn)

        default:
            break
        }
    }

    /// `ms.channel.unauthorized` has three distinct causes and only one of
    /// them should cost us the stored token:
    ///
    /// 1. The TV is still booting (we connected too early after a wake or a
    ///    power blip) and its remote-control service hasn't loaded the
    ///    paired-device list yet. The token is fine — retry with it.
    /// 2. The TV genuinely no longer knows the token (Smart Hub reset,
    ///    device removed from Device Connection Manager). Clear it and
    ///    re-pair; the TV shows one Allow prompt.
    /// 3. The user pressed Deny, so the TV has this device name blocked.
    ///    Reconnecting without a token won't help — stop and tell them where
    ///    to unblock it on the TV.
    ///
    /// Dropping the token on the first reply (what we used to do) turned
    /// every case-1 hiccup into a fresh pairing prompt.
    private func handleUnauthorized() {
        cancelSocket()
        pingTask?.cancel()

        guard let tv = settings.activeTV else {
            status = .failed("TV denied access.")
            wantsConnection = false
            return
        }

        if tv.token != nil, unauthorizedWithTokenCount < maxUnauthorizedRetriesWithToken {
            unauthorizedWithTokenCount += 1
            let delayNS = UInt64(unauthorizedWithTokenCount) * 2_000_000_000 // 2 s, 4 s, 6 s
            DiagnosticLog.shared.log(
                "ms.channel.unauthorized with stored token (\(unauthorizedWithTokenCount)/\(maxUnauthorizedRetriesWithToken)) — TV may still be booting; retrying with the same token in \(delayNS / 1_000_000_000) s",
                level: .warn
            )
            status = .reconnecting
            connectTask?.cancel()
            connectTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delayNS)
                await self?.connectAsync()
            }
            return
        }

        if tv.token != nil {
            settings.forgetPairing(id: tv.id)
            UserDefaults.standard.synchronize()
            unauthorizedWithTokenCount = 0
            DiagnosticLog.shared.log(
                "ms.channel.unauthorized \(maxUnauthorizedRetriesWithToken)× with stored token — token cleared, requesting fresh pair",
                level: .warn
            )
            status = .awaitingPairing
            startConnect()
            return
        }

        DiagnosticLog.shared.log(
            "ms.channel.unauthorized without a token — the TV has “\(settings.deviceName)” blocked",
            level: .warn
        )
        status = .failed(
            "TV denied access. On the TV open Settings ▸ General ▸ External Device Manager ▸ Device Connection Manager ▸ Device List and allow “\(settings.deviceName)”, then tap Connect."
        )
        wantsConnection = false
    }

    private func normalisedData(from raw: Any?) -> [String: Any]? {
        if let dict = raw as? [String: Any] { return dict }
        if let string = raw as? String,
           let data = string.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return nil
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
              !value.isEmpty, value != "0", value.lowercased() != "null"
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
