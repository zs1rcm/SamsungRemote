import SwiftUI

@main
struct SamsungRemoteApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var client: SamsungTVClient

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _client = StateObject(wrappedValue: SamsungTVClient(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(client)
        }
    }
}
