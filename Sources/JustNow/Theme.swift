import AppKit
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.47, green: 0.40, blue: 0.92)
    static let background = adaptive(light: 0xF8F7F4, dark: 0x171719)
    static let sidebar = adaptive(light: 0xF0EFEC, dark: 0x1E1E22)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x252529)
    static let inset = adaptive(light: 0xF6F5F3, dark: 0x1D1D21)
    static let ink = adaptive(light: 0x28262E, dark: 0xF1F0F4)
    static let secondary = adaptive(light: 0x797681, dark: 0xACA9B6)
    static let line = adaptive(light: 0xE9E7ED, dark: 0x35353C)
    static let amber = adaptive(light: 0xA36B22, dark: 0xEBC383)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct BrandMark: View {
    var size: CGFloat = 38
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.accent.gradient)
            Path { path in
                let left = size * 0.23, top = size * 0.21
                let width = size * 0.54, height = size * 0.51
                path.addRoundedRect(in: CGRect(x: left, y: top, width: width, height: height), cornerSize: CGSize(width: size * 0.13, height: size * 0.13))
                path.move(to: CGPoint(x: size * 0.40, y: size * 0.72))
                path.addLine(to: CGPoint(x: size * 0.32, y: size * 0.80))
                path.addLine(to: CGPoint(x: size * 0.32, y: size * 0.69))
            }
            .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round, lineJoin: .round))
            Path { path in
                path.move(to: CGPoint(x: size * 0.51, y: size * 0.32))
                path.addLine(to: CGPoint(x: size * 0.51, y: size * 0.47))
                path.addLine(to: CGPoint(x: size * 0.62, y: size * 0.52))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ActionButtonStyle: ButtonStyle {
    var primary = true
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 8 : 12)
            .foregroundStyle(primary ? Color.white : Theme.ink)
            .background(primary ? Theme.accent : Theme.inset, in: RoundedRectangle(cornerRadius: compact ? 9 : 11))
            .overlay(RoundedRectangle(cornerRadius: compact ? 9 : 11).stroke(primary ? .clear : Theme.line, lineWidth: 1))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? Theme.line : Theme.inset, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func journalCard(padding: CGFloat = 24) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Theme.line.opacity(0.85), lineWidth: 1))
    }
}
