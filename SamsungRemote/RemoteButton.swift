import SwiftUI

struct RemoteButton: View {
    enum Style {
        case standard
        case primary
        case destructive
        case colored(Color)
    }

    let title: String?
    let systemImage: String?
    var style: Style = .standard
    var action: () -> Void

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        style: Style = .standard,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(background)
                    .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

                Group {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 22, weight: .semibold))
                    } else if let title {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                    }
                }
                .foregroundStyle(foreground)
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch style {
        case .standard:           return Color(white: 0.18)
        case .primary:            return .accentColor
        case .destructive:        return .red
        case .colored(let color): return color
        }
    }

    private var foreground: Color {
        switch style {
        case .standard: return .white
        default:        return .white
        }
    }
}

struct WideRemoteButton: View {
    let title: String
    let systemImage: String?
    var action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(white: 0.18), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
