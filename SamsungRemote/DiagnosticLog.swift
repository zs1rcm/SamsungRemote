import Foundation

@MainActor
final class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let time: Date
        let level: Level
        let message: String
    }

    enum Level: String {
        case info, warn, error, event

        var symbol: String {
            switch self {
            case .info:  return "•"
            case .warn:  return "!"
            case .error: return "✕"
            case .event: return "↓"
            }
        }
    }

    @Published private(set) var entries: [Entry] = []
    private let maxEntries = 200
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    func log(_ message: String, level: Level = .info) {
        let entry = Entry(time: Date(), level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        // Also route to Xcode console so it's visible with the debugger attached.
        print("[remote \(level.symbol)] \(message)")
    }

    func clear() {
        entries.removeAll()
    }

    func formatted(_ entry: Entry) -> String {
        "\(formatter.string(from: entry.time))  \(entry.level.symbol)  \(entry.message)"
    }
}
