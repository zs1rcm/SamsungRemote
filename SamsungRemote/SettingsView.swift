import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var client: SamsungTVClient
    @StateObject private var discovery = TVDiscovery()
    @Environment(\.dismiss) private var dismiss

    @State private var deviceName: String = ""
    @State private var showManualAdd = false

    var body: some View {
        NavigationStack {
            Form {
                savedSection
                discoverySection
                manualSection
                deviceSection
                diagnosticsSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        commitDeviceName()
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear { deviceName = settings.deviceName }
            .sheet(isPresented: $showManualAdd) {
                ManualAddTVView()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var savedSection: some View {
        Section("My TVs") {
            if settings.savedTVs.isEmpty {
                Text("No TVs saved yet. Use Scan below or Add Manually.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings.savedTVs) { tv in
                    Button {
                        settings.setActive(tv.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tv.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if !tv.subtitle.isEmpty {
                                    Text(tv.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(tv.token != nil ? "Paired" : "Not paired")
                                    .font(.caption2)
                                    .foregroundStyle(tv.token != nil ? .green : .orange)
                            }
                            Spacer()
                            if settings.activeTV?.id == tv.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            settings.remove(id: tv.id)
                        } label: { Label("Delete", systemImage: "trash") }

                        if tv.token != nil {
                            Button {
                                settings.forgetPairing(id: tv.id)
                            } label: { Label("Forget", systemImage: "key.slash") }
                            .tint(.orange)
                        }

                        if let mac = tv.effectiveMAC {
                            Button {
                                WakeOnLAN.wake(mac: mac)
                            } label: { Label("Wake", systemImage: "power") }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var discoverySection: some View {
        Section("Discover") {
            Button {
                Task { await discovery.scan() }
            } label: {
                HStack {
                    if discovery.isScanning {
                        ProgressView().controlSize(.small)
                        Text("Scanning network…")
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Scan for TVs")
                    }
                    Spacer()
                }
            }
            .disabled(discovery.isScanning)

            if let error = discovery.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(discovery.results) { result in
                Button {
                    let tv = SavedTV(
                        id: result.id,
                        name: result.name,
                        modelName: result.modelName,
                        host: result.host,
                        mac: result.mac,
                        useTLS: true,
                        token: nil
                    )
                    settings.upsert(tv, makeActive: true)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name).foregroundStyle(.primary)
                            Text([result.modelName, result.host]
                                .compactMap { $0 }
                                .joined(separator: " · ")
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.savedTVs.contains(where: { $0.id == result.id }) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var manualSection: some View {
        Section {
            Button {
                showManualAdd = true
            } label: {
                Label("Add TV by IP…", systemImage: "plus")
            }
        } footer: {
            Text("Most TVs are assigned a new IP over time (DHCP). Samsung Remote saves each TV by its MAC address and automatically finds it again when the IP changes.")
        }
    }

    @ViewBuilder
    private var deviceSection: some View {
        Section("This device") {
            TextField("iPhone Remote", text: $deviceName)
                .textInputAutocapitalization(.words)
                .onSubmit(commitDeviceName)
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                DiagnosticLogView()
            } label: {
                Label("Connection log", systemImage: "text.viewfinder")
            }
        } footer: {
            Text("Open this if the TV re-prompts to allow the remote. It shows every message from the TV so you can see whether the pairing token was actually sent back.")
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            Text("Samsung Tizen TVs (2016+) expose a WebSocket remote on ports 8001 (ws) and 8002 (wss). On first connect the TV shows a pairing prompt — accept it and the returned token is stored for future reconnects.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Wake-on-LAN sends a magic packet to the TV's MAC address. It only works if the TV is wired via Ethernet (Samsungs power down Wi-Fi in deep standby) and \"Power On with Mobile\" is enabled on the TV: Settings ▸ General ▸ Network ▸ Expert Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func commitDeviceName() {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.deviceName = trimmed.isEmpty ? "iPhone Remote" : trimmed
    }
}

// MARK: - Diagnostic log viewer

private struct DiagnosticLogView: View {
    @ObservedObject private var log = DiagnosticLog.shared

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("No events yet. Tap Connect on the main screen to start logging.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(log.entries.reversed()) { entry in
                    Text(log.formatted(entry))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(color(for: entry.level))
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
        }
        .navigationTitle("Connection log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { log.clear() }
                    .disabled(log.entries.isEmpty)
            }
        }
    }

    private func color(for level: DiagnosticLog.Level) -> Color {
        switch level {
        case .info:  return .primary
        case .event: return .blue
        case .warn:  return .orange
        case .error: return .red
        }
    }
}

// MARK: - Manual add

private struct ManualAddTVView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var host: String = ""
    @State private var nickname: String = ""
    @State private var useTLS: Bool = true
    @State private var probing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("TV") {
                    TextField("192.168.1.42", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Nickname (optional)", text: $nickname)
                    Toggle("Use TLS (port 8002)", isOn: $useTLS)
                }

                if let message {
                    Section { Text(message).font(.footnote) }
                }

                Section {
                    Button {
                        Task { await addTV() }
                    } label: {
                        if probing {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Add TV")
                        }
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || probing)
                }
            }
            .navigationTitle("Add TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addTV() async {
        probing = true
        defer { probing = false }

        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prefer a MAC-keyed entry by probing, but fall back to a host-keyed
        // one so the user can still save a device that doesn't answer right
        // now (e.g. TV is off).
        if let probed = await TVScanner.probe(host: trimmed, timeout: 2.5) {
            let tv = SavedTV(
                id: probed.id,
                name: nickname.isEmpty ? probed.name : nickname,
                modelName: probed.modelName,
                host: probed.host,
                mac: probed.mac,
                useTLS: useTLS,
                token: nil
            )
            settings.upsert(tv, makeActive: true)
            dismiss()
        } else {
            let tv = SavedTV(
                id: trimmed,
                name: nickname.isEmpty ? trimmed : nickname,
                modelName: nil,
                host: trimmed,
                mac: nil,
                useTLS: useTLS,
                token: nil
            )
            settings.upsert(tv, makeActive: true)
            message = "Couldn't reach the TV right now — saved anyway. Turn the TV on and press Connect, or tap Scan later to pick up its MAC address for Wake-on-LAN."
        }
    }
}
