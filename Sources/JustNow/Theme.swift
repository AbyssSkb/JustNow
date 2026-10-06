import AppKit
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.47, green: 0.40, blue: 0.92)
    static let background = adaptive(light: 0xF8F7F4, dark: 0x171719)
    static let sidebar = adaptive(light: 0xF0EFEC, dark: 0x1E1E22)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x252529)
    static let inset = adaptive(light: 0xF6F5F3, dark: 0x1D1D21)
    static let ink = adaptive(light: 0x28262E, dark: 0xF1F0F4)
    static let secondary = adaptive(light: 0x6D6A75, dark: 0xB6B3C0)
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
    private static let image = NSImage(contentsOf:
        (Bundle.main.url(forResource: "BrandMark", withExtension: "png")
         ?? Bundle.module.url(forResource: "BrandMark", withExtension: "png"))!)!

    var body: some View {
        Image(nsImage: Self.image)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .scaleEffect(1.16) // Compensate for the source canvas margin.
            .accessibilityHidden(true)
    }
}

struct ActionButtonStyle: ButtonStyle {
    var primary = true
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        ButtonSurface(configuration: configuration, primary: primary, compact: compact)
    }
}

struct IconButtonStyle: ButtonStyle {
    var compact = true
    func makeBody(configuration: Configuration) -> some View {
        ButtonSurface(configuration: configuration, primary: false, compact: compact, iconOnly: true)
    }
}

private struct ButtonSurface: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    let compact: Bool
    var iconOnly = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
        configuration.label
            .foregroundStyle(primary ? Color.white : iconOnly ? Theme.secondary : Theme.ink)
            .background(primary ? Theme.accent : hovering && isEnabled ? Theme.line : Theme.inset, in: shape)
            .overlay(shape.strokeBorder(primary ? .clear : Theme.line, lineWidth: 1))
            .brightness(primary && hovering && isEnabled ? 0.035 : 0)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.72 : 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct JournalToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.accent : Theme.secondary.opacity(0.25))
                Circle().fill(.white).frame(width: 20, height: 20).padding(3)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            }
            .frame(width: 44, height: 26)
            .frame(width: 56, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

extension View {
    func actionLabel(compact: Bool = false, iconOnly: Bool = false) -> some View {
        self.font(.system(size: compact ? 12 : 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, iconOnly ? 0 : compact ? 12 : 18)
            .frame(width: iconOnly ? (compact ? 36 : 40) : nil, height: compact ? 36 : 40)
            .contentShape(RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous))
    }

    func journalCard(padding: CGFloat = 24) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Theme.line.opacity(0.85), lineWidth: 1))
    }
}
