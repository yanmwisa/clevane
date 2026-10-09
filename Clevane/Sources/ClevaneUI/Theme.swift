import AppKit
import SwiftUI

/// Direction D tokens (prototype/design.css), light and dark. Black, white and grey only;
/// red is reserved for destructive actions.
enum Palette {
    static let window = dynamic(light: 0xF9F9F8, dark: 0x1C1C1E)
    static let panel = dynamic(light: 0xECECEE, dark: 0x2C2C2F)
    static let sheet = dynamic(light: 0xFFFFFF, dark: 0x2A2A2D)
    static let text = dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let text2 = dynamic(light: 0x3A3A3C, dark: 0xD1D1D6)
    static let muted = dynamic(light: 0x636366, dark: 0xA1A1A6)
    static let quiet = dynamic(light: 0x6E6E73, dark: 0x98989D)
    static let field = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let controlLine = dynamic(light: 0x8E8E93, dark: 0x8E8E93)
    static let ink = dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let onInk = dynamic(light: 0xFFFFFF, dark: 0x1D1D1F)
    static let danger = dynamic(light: 0xC41A1A, dark: 0xFF6961)
    static let line = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.08)
    static let line2 = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.13)
    static let select = dynamic(light: 0x000000, dark: 0xFFFFFF, alpha: 0.065)
    static let tile = LinearGradient(colors: [dynamic(light: 0x48484A, dark: 0x6E6E73), dynamic(light: 0x2C2C2E, dark: 0x3A3A3C)], startPoint: .top, endPoint: .bottom)
    static let softTile = LinearGradient(colors: [dynamic(light: 0xF4F4F6, dark: 0x3A3A3C), dynamic(light: 0xE3E3E7, dark: 0x2C2C2E)], startPoint: .top, endPoint: .bottom)

    private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light, alpha: alpha)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

/// New York (the system serif) carries the editorial voice; SF Pro carries the interface.
extension Font {
    static func serif(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func serifItalic(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif).italic()
    }

    static let value = Font.system(size: 14, design: .monospaced)
}

/// Small spaced capitals used for labels and kickers.
struct Caps: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Palette.muted)
    }
}

// MARK: - Tiles

/// Graphite squircle: section icons, table monograms, app icon.
struct Tile<Content: View>: View {
    var size: CGFloat = 24
    var isSoft = false
    @ViewBuilder var content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(isSoft ? Palette.softTile : Palette.tile)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .strokeBorder(isSoft ? Palette.line2 : Color.white.opacity(0.12), lineWidth: 0.5)
            }
            .overlay { content.foregroundStyle(isSoft ? Palette.text2 : Color.white) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Tables are user-defined and have no chosen icon, so their tile shows the table's initial.
struct MonogramTile: View {
    let name: String
    var size: CGFloat = 24
    var isSoft = false

    var body: some View {
        Tile(size: size, isSoft: isSoft) {
            Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.serif(size * 0.62))
        }
    }
}

struct SymbolTile: View {
    let systemName: String
    var size: CGFloat = 24
    var isSoft = false

    var body: some View {
        Tile(size: size, isSoft: isSoft) {
            Image(systemName: systemName).font(.system(size: size * 0.5, weight: .medium))
        }
    }
}

struct AppIconTile: View {
    var size: CGFloat = 76

    var body: some View {
        Tile(size: size) {
            BrandMark().frame(width: size * 0.42, height: size * 0.52)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}

/// The C-shaped padlock of the Clevane logo, from the prototype's SVG (viewBox 100 x 125).
struct BrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 100, rect.height / 125)
        let origin = CGPoint(x: rect.midX - 50 * scale, y: rect.midY - 62.5 * scale)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        var shackle = Path()
        shackle.move(to: point(25, 46))
        shackle.addLine(to: point(25, 28))
        shackle.addCurve(to: point(50, 0), control1: point(25, 10), control2: point(36, 0))
        shackle.addCurve(to: point(75, 28), control1: point(64, 0), control2: point(75, 10))
        shackle.addLine(to: point(75, 46))
        shackle.addLine(to: point(63, 46))
        shackle.addLine(to: point(63, 28))
        shackle.addCurve(to: point(50, 12), control1: point(63, 18), control2: point(58, 12))
        shackle.addCurve(to: point(37, 28), control1: point(42, 12), control2: point(37, 18))
        shackle.addLine(to: point(37, 46))
        shackle.closeSubpath()
        var body = Path()
        body.move(to: point(83, 42))
        body.addCurve(to: point(56, 34), control1: point(78, 35), control2: point(68, 34))
        body.addLine(to: point(35, 34))
        body.addCurve(to: point(8, 63), control1: point(16, 34), control2: point(8, 45))
        body.addLine(to: point(8, 91))
        body.addCurve(to: point(35, 119), control1: point(8, 110), control2: point(17, 119))
        body.addLine(to: point(62, 119))
        body.addCurve(to: point(93, 93), control1: point(79, 119), control2: point(91, 110))
        body.addLine(to: point(77, 93))
        body.addCurve(to: point(60, 104), control1: point(75, 101), control2: point(70, 104))
        body.addLine(to: point(39, 104))
        body.addCurve(to: point(24, 90), control1: point(29, 104), control2: point(24, 100))
        body.addLine(to: point(24, 64))
        body.addCurve(to: point(39, 49), control1: point(24, 54), control2: point(29, 49))
        body.addLine(to: point(61, 49))
        body.addCurve(to: point(77, 63), control1: point(70, 49), control2: point(75, 54))
        body.addLine(to: point(93, 63))
        body.addCurve(to: point(83, 42), control1: point(93, 55), control2: point(90, 48))
        body.closeSubpath()
        // The two outlines turn in opposite directions; a true union keeps their overlap filled.
        return shackle.union(body)
    }
}

// MARK: - Buttons

/// Ink capsule: the one main action of a screen.
struct InkButtonStyle: ButtonStyle {
    var isWide = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.onInk)
            .padding(.horizontal, 16)
            .frame(maxWidth: isWide ? .infinity : nil, minHeight: 34)
            .background(Capsule().fill(Palette.ink))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Glass capsule: secondary actions.
struct CapsuleButtonStyle: ButtonStyle {
    var isWide = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 14)
            .frame(maxWidth: isWide ? .infinity : nil, minHeight: 32)
            .background(Capsule().fill(Palette.sheet))
            .overlay(Capsule().strokeBorder(Palette.line2, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Round icon button (Copy, Show, options).
struct IconButtonStyle: ButtonStyle {
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text2)
            .frame(width: 30, height: 30)
            .background(Circle().fill(isActive || configuration.isPressed ? Palette.select : .clear))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Copy with a short checkmark confirmation, shared by row details and the passphrase card.
struct CopyButton: View {
    let accessibilityName: String
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            action()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: copied)
        }
        .buttonStyle(IconButtonStyle(isActive: copied))
        .accessibilityLabel(accessibilityName)
    }
}

/// Bordered field with a 3:1 boundary, shared by every form.
struct FieldBox<Content: View>: View {
    var isFocused = false
    var isPill = false
    @ViewBuilder var content: Content

    /// A pill uses circular corners at half the 36 pt height: continuous corners there flatten the sides,
    /// which showed as a thin vertical edge beside the search field.
    private var outline: RoundedRectangle {
        isPill ? RoundedRectangle(cornerRadius: 18, style: .circular) : RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(outline.fill(Palette.field))
            .overlay {
                outline
                    .strokeBorder(isFocused ? Palette.text : Palette.controlLine, lineWidth: 1)
            }
    }
}

/// Label above a field, in small capitals.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Caps(label)
            content
        }
    }
}

/// Text or secure field with a Show/Hide button, used for passwords and Secret columns.
struct SecretField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    /// Lets a parent show the value, e.g. a passphrase Clevane just filled in; otherwise the field keeps its own state.
    var reveal: Binding<Bool>?
    @State private var ownReveal = false

    private var isRevealed: Bool {
        get { reveal?.wrappedValue ?? ownReveal }
        nonmutating set { if let reveal { reveal.wrappedValue = newValue } else { ownReveal = newValue } }
    }

    var body: some View {
        FieldBox {
            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .accessibilityLabel(label)
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .accessibilityLabel(isRevealed ? "Hide \(label)" : "Show \(label)")
            }
        }
    }
}

/// Source of the app icon (1024 px canvas, macOS icon grid: 824 px tile). Exported by the snapshot run,
/// then turned into AppIcon.icns by scripts/make-icon.sh.
struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.31), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 2))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
            BrandMark()
                .fill(Color.white)
                .frame(width: 330, height: 412)
        }
        .frame(width: 1024, height: 1024)
    }
}
