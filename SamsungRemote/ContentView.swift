import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var client: SamsungTVClient

    @State private var showSettings = false
    @State private var showNumberPad = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.08), .black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        statusCard
                        topRow
                        volumeChannelRow
                        dPad
                        mediaRow
                        bottomRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Samsung Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showNumberPad = true } label: {
                        Image(systemName: "number")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showNumberPad) {
                NumberPadView()
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Sections

    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.subheadline.weight(.semibold))
                Text(secondaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if case .connected = client.status {
                    client.disconnect()
                } else {
                    client.connect()
                }
            } label: {
                Text(client.status == .connected ? "Disconnect" : "Connect")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(settings.activeTV == nil ? Color.gray : Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(settings.activeTV == nil)
        }
        .padding(14)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var primaryLine: String {
        if let tv = settings.activeTV {
            return tv.displayName
        }
        return "No TV selected"
    }

    private var secondaryLine: String {
        guard let tv = settings.activeTV else {
            return "Tap the gear icon → Scan"
        }
        return "\(client.status.label) · \(tv.host):\(tv.port)"
    }

    private var topRow: some View {
        HStack(spacing: 18) {
            RemoteButton(systemImage: "power", style: .destructive) { client.send(.power) }
            Spacer()
            RemoteButton(systemImage: "tv.inset.filled") { client.send(.source) }
            RemoteButton(systemImage: "house.fill") { client.send(.home) }
            RemoteButton(systemImage: "arrow.uturn.backward") { client.send(.back) }
        }
    }

    private var volumeChannelRow: some View {
        HStack(spacing: 18) {
            verticalPad(
                topIcon: "plus",
                bottomIcon: "minus",
                middleIcon: "speaker.slash.fill",
                topAction: { client.send(.volumeUp) },
                bottomAction: { client.send(.volumeDown) },
                middleAction: { client.send(.mute) },
                label: "VOL"
            )
            Spacer()
            verticalPad(
                topIcon: "plus",
                bottomIcon: "minus",
                middleIcon: "list.bullet",
                topAction: { client.send(.channelUp) },
                bottomAction: { client.send(.channelDown) },
                middleAction: { client.send(.channelList) },
                label: "CH"
            )
        }
    }

    private func verticalPad(
        topIcon: String, bottomIcon: String, middleIcon: String,
        topAction: @escaping () -> Void,
        bottomAction: @escaping () -> Void,
        middleAction: @escaping () -> Void,
        label: String
    ) -> some View {
        VStack(spacing: 6) {
            RemoteButton(systemImage: topIcon, action: topAction)
            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
            RemoteButton(systemImage: middleIcon, action: middleAction)
            RemoteButton(systemImage: bottomIcon, action: bottomAction)
        }
    }

    private var dPad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(white: 0.12))
                .frame(height: 260)

            VStack(spacing: 8) {
                RemoteButton(systemImage: "chevron.up") { client.send(.up) }
                HStack(spacing: 8) {
                    RemoteButton(systemImage: "chevron.left") { client.send(.left) }
                    RemoteButton("OK", style: .primary) { client.send(.enter) }
                    RemoteButton(systemImage: "chevron.right") { client.send(.right) }
                }
                RemoteButton(systemImage: "chevron.down") { client.send(.down) }
            }
        }
    }

    private var mediaRow: some View {
        HStack(spacing: 10) {
            RemoteButton(systemImage: "backward.fill") { client.send(.rewind) }
            RemoteButton(systemImage: "play.fill") { client.send(.play) }
            RemoteButton(systemImage: "pause.fill") { client.send(.pause) }
            RemoteButton(systemImage: "stop.fill") { client.send(.stop) }
            RemoteButton(systemImage: "forward.fill") { client.send(.fastForward) }
        }
    }

    private var bottomRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                WideRemoteButton("Menu", systemImage: "slider.horizontal.3") { client.send(.menu) }
                WideRemoteButton("Guide", systemImage: "calendar") { client.send(.guide) }
                WideRemoteButton("Tools", systemImage: "wrench.and.screwdriver") { client.send(.tools) }
            }
            HStack(spacing: 10) {
                WideRemoteButton("Info", systemImage: "info.circle") { client.send(.info) }
                WideRemoteButton("Exit", systemImage: "xmark.circle") { client.send(.exit) }
            }
            HStack(spacing: 10) {
                colorPip(.red)    { client.send(.red) }
                colorPip(.green)  { client.send(.green) }
                colorPip(.yellow) { client.send(.yellow) }
                colorPip(.blue)   { client.send(.blue) }
            }
            .padding(.top, 4)
        }
    }

    private func colorPip(_ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Capsule()
                .fill(color)
                .frame(height: 28)
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch client.status {
        case .connected:                                 return .green
        case .connecting, .awaitingPairing, .resolving:  return .yellow
        case .failed:                                    return .red
        case .disconnected:                              return .gray
        }
    }
}

// MARK: - Number pad sheet

struct NumberPadView: View {
    @EnvironmentObject var client: SamsungTVClient
    @Environment(\.dismiss) private var dismiss

    private let rows: [[Int]] = [[1,2,3],[4,5,6],[7,8,9]]

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 14) {
                        ForEach(row, id: \.self) { n in
                            digitButton(n)
                        }
                    }
                }
                HStack(spacing: 14) {
                    Spacer().frame(width: 64)
                    digitButton(0)
                    Button {
                        client.send(.enter)
                        dismiss()
                    } label: {
                        Text("Enter")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .center)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func digitButton(_ n: Int) -> some View {
        RemoteButton("\(n)") {
            if let key = TVKey.digit(n) { client.send(key) }
        }
    }
}
