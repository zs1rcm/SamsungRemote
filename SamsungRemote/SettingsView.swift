import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var client: SamsungTVClient
    @Environment(\.dismiss) private var dismiss

    @State private var host: String = ""
    @State private var useTLS: Bool = true
    @State private var deviceName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("TV") {
                    TextField("192.168.1.42", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Use TLS (port 8002)", isOn: $useTLS)
                    LabeledContent("Port") {
                        Text("\(useTLS ? 8002 : 8001)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("This device") {
                    TextField("iPhone Remote", text: $deviceName)
                        .textInputAutocapitalization(.words)
                }

                Section("Pairing") {
                    LabeledContent("Token") {
                        Text(settings.token?.isEmpty == false ? "Saved" : "None")
                            .foregroundStyle(.secondary)
                    }
                    Button("Forget pairing", role: .destructive) {
                        settings.forgetPairing()
                    }
                    .disabled(settings.token == nil)
                }

                Section {
                    Text("Samsung Tizen TVs (2016+) expose a WebSocket remote on ports 8001 (ws) and 8002 (wss). On first connect the TV prompts you to allow the remote; accept it and the returned token is stored for future connections.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        settings.tvHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
                        settings.useTLS = useTLS
                        settings.deviceName = deviceName.isEmpty ? "iPhone Remote" : deviceName
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                host = settings.tvHost
                useTLS = settings.useTLS
                deviceName = settings.deviceName
            }
        }
    }
}
