import CoreText
import SwiftUI
import UIKit

// The Lugipod look, taken from the website (src/app/globals.css): refined indigo brand, amber for
// coins and the "פוד" in the wordmark, Heebo, a soft near-white page, big rounded white cards with
// layered shadows, and Lugi the fox. Everything in the app is built from these pieces so the iPad
// app and the website read as one product.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    // Brand (tailwind indigo, as in the site's @theme)
    static let brand50 = Color(hex: 0xEEF2FF)
    static let brand100 = Color(hex: 0xE0E7FF)
    static let brand200 = Color(hex: 0xC7D2FE)
    static let brand300 = Color(hex: 0xA5B4FC)
    static let brand400 = Color(hex: 0x818CF8)
    static let brand500 = Color(hex: 0x6366F1)
    static let brand600 = Color(hex: 0x4F46E5)
    static let brand700 = Color(hex: 0x4338CA)
    static let brand800 = Color(hex: 0x3730A3)
    static let brand900 = Color(hex: 0x312E81)
    static let violet500 = Color(hex: 0x8B5CF6)
    static let violet700 = Color(hex: 0x6D28D9)
    static let violet50 = Color(hex: 0xF5F3FF)

    // Page + text
    static let page = Color(hex: 0xF7F8FC)
    static let ink = Color(hex: 0x0F172A)
    static let slate50 = Color(hex: 0xF8FAFC)
    static let slate100 = Color(hex: 0xF1F5F9)
    static let slate200 = Color(hex: 0xE2E8F0)
    static let slate300 = Color(hex: 0xCBD5E1)
    static let slate400 = Color(hex: 0x94A3B8)
    static let slate500 = Color(hex: 0x64748B)
    static let slate600 = Color(hex: 0x475569)
    static let slate700 = Color(hex: 0x334155)

    // Accents
    static let amber50 = Color(hex: 0xFFFBEB)
    static let amber100 = Color(hex: 0xFEF3C7)
    static let amber200 = Color(hex: 0xFDE68A)
    static let amber400 = Color(hex: 0xFBBF24)
    static let amber500 = Color(hex: 0xF59E0B)
    static let amber800 = Color(hex: 0x92400E)
    static let emerald50 = Color(hex: 0xECFDF5)
    static let emerald100 = Color(hex: 0xD1FAE5)
    static let emerald200 = Color(hex: 0xA7F3D0)
    static let emerald500 = Color(hex: 0x10B981)
    static let emerald600 = Color(hex: 0x059669)
    static let emerald700 = Color(hex: 0x047857)
    static let rose50 = Color(hex: 0xFFF1F2)
    static let rose500 = Color(hex: 0xF43F5E)
    static let rose600 = Color(hex: 0xE11D48)
    static let orange100 = Color(hex: 0xFFEDD5)
    static let orange300 = Color(hex: 0xFDBA74)
    static let sky50 = Color(hex: 0xF0F9FF)
    static let sky200 = Color(hex: 0xBAE6FD)
    static let sky800 = Color(hex: 0x075985)

    // The fox's orange and the gold of the lugi coin: the app's warm side, used boldly (calls to action, dates, coins).
    static let orange400 = Color(hex: 0xFB923C)
    static let orange500 = Color(hex: 0xF97316)
    static let orange600 = Color(hex: 0xEA580C)
    static let orange700 = Color(hex: 0xC2410C)
    static let gold300 = Color(hex: 0xFDE047)
    static let gold500 = Color(hex: 0xF59E0B)
    static let gold700 = Color(hex: 0xB45309)

    // Gradients
    /// The big indigo block at the top of the app.
    static let hero = LinearGradient(colors: [Color(hex: 0x6366F1), Color(hex: 0x7C6CF5), Color(hex: 0xA78BFA)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cta = LinearGradient(colors: [orange400, orange600], startPoint: .top, endPoint: .bottom)
    static let indigoButton = LinearGradient(colors: [brand500, brand700], startPoint: .top, endPoint: .bottom)
    static let coin = LinearGradient(colors: [gold300, gold500, Color(hex: 0xD97706)], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The website's `shadow-soft`.
    static let shadowSoft1 = Color(hex: 0x0F172A, opacity: 0.04)
    static let shadowSoft2 = Color(hex: 0x0F172A, opacity: 0.06)
}

// MARK: - Heebo

/// Heebo is a variable font (weight axis 100–900); the weight is set per use. If the font file did
/// not load for any reason the system font is used, so text never disappears.
enum Heebo {
    private static let weightAxis = NSNumber(value: 0x77676874) // 'wght'

    static var isAvailable: Bool { UIFont.familyNames.contains("Heebo") }

    static func uiFont(_ size: CGFloat, _ weight: CGFloat) -> UIFont {
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = UIFontDescriptor(fontAttributes: [.family: "Heebo"])
            .addingAttributes([variation: [weightAxis: NSNumber(value: Double(weight))]])
        let font = UIFont(descriptor: descriptor, size: size)
        return font.familyName == "Heebo" ? font : .systemFont(ofSize: size, weight: systemWeight(weight))
    }

    private static func systemWeight(_ w: CGFloat) -> UIFont.Weight {
        switch w {
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }
}

extension Font {
    /// `weight` is the CSS number: 400 regular, 500 medium, 600 semibold, 700 bold, 800 extrabold, 900 black.
    static func heebo(_ size: CGFloat, _ weight: CGFloat = 500) -> Font {
        Font(Heebo.uiFont(size, weight) as CTFont)
    }
}

// MARK: - Surfaces

/// The website's page background: soft near-white with a blurred indigo glow at the top and an
/// amber one bottom-left.
struct ScreenBackground: View {
    var body: some View {
        // Two radial gradients instead of two full-screen 100 pt Gaussian blurs: the same glow, but a blur that large is re-rendered by
        // the GPU on every scroll frame (the main reason the first build felt heavy, most of all on an iPad's big screen).
        ZStack {
            Theme.page
            RadialGradient(colors: [Theme.brand300.opacity(0.70), Theme.brand300.opacity(0)], center: .init(x: 0.5, y: -0.02), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.orange300.opacity(0.55), Theme.orange300.opacity(0)], center: .init(x: 0.12, y: 1.0), startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
        .drawingGroup()
    }
}

extension View {
    /// A white card, as on the website (`rounded-3xl border border-slate-200 bg-white card-soft`).
    func card(padding: CGFloat = 20, radius: CGFloat = 24, fill: Color = .white, border: Color = Theme.slate200) -> some View {
        self
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 1))
            .shadow(color: Theme.shadowSoft1, radius: 1, y: 1)
            .shadow(color: Theme.shadowSoft2, radius: 8, y: 4)
    }
}

/// A scrolling screen with the page background and a centered column, so nothing stretches edge to
/// edge on an iPad.
struct Scaffold<Content: View>: View {
    var maxWidth: CGFloat = 820
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 18, content: content)
                .frame(maxWidth: maxWidth)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(ScreenBackground())
    }
}

struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.heebo(32, 800)).foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle).font(.heebo(15, 500)).foregroundStyle(Theme.slate500)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionTitle: View {
    let text: String
    var count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(.heebo(19, 800)).foregroundStyle(Theme.ink)
            if let count, count > 0 {
                Text("\(count)").font(.heebo(13, 800)).foregroundStyle(Theme.brand700)
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(Theme.brand100, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heebo(17, 700))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(enabled ? AnyShapeStyle(Theme.indigoButton) : AnyShapeStyle(Theme.brand300)) }
            .shadow(color: enabled ? Theme.brand700.opacity(0.40) : .clear, radius: 12, y: 6)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heebo(16, 700))
            .foregroundStyle(Theme.brand700)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.brand200, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

/// The warm call to action: the fox's orange.
struct CTAButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heebo(17, 800))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(enabled ? AnyShapeStyle(Theme.cta) : AnyShapeStyle(Theme.orange300)) }
            .shadow(color: enabled ? Theme.orange600.opacity(0.45) : .clear, radius: 12, y: 6)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

/// A small tinted button (brand by default) for secondary actions inside cards.
struct SoftButtonStyle: ButtonStyle {
    var fg: Color = Theme.brand700
    var bg: Color = Theme.brand50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heebo(14, 700))
            .foregroundStyle(fg)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(bg, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

// MARK: - Small pieces

struct Pill: View {
    let text: String
    var icon: String?
    var fg: Color = Theme.brand700
    var bg: Color = Theme.brand50

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            Text(text).font(.heebo(13, 700))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(bg, in: Capsule())
    }
}

/// "לוגיפוד" with the indigo "לוגי" and the amber "פוד", as in the site's header.
struct Wordmark: View {
    var size: CGFloat = 30

    var body: some View {
        (Text("לוגי").foregroundStyle(Theme.brand600) + Text("פוד").foregroundStyle(Theme.amber500))
            .font(.heebo(size, 900))
    }
}

enum LugiPose: String {
    case wave, sit, study, cheer, praise, peek, wink, proud, walk
}

/// Lugi the fox (illustrated, from the website's pose set), with a slow breathing motion.
struct Lugi: View {
    let pose: LugiPose
    var height: CGFloat = 140
    var breathing = false
    @State private var inhaled = false

    var body: some View {
        Image("Lugi-\(pose.rawValue)")
            .resizable().scaledToFit()
            .frame(height: height)
            .scaleEffect(x: 1, y: breathing && inhaled ? 1.015 : 1, anchor: .bottom)
            .animation(breathing ? .easeInOut(duration: 2.6).repeatForever(autoreverses: true) : nil, value: inhaled)
            .onAppear { inhaled = true }
            .accessibilityHidden(true)
    }
}

/// A labelled text box in the site's form style: slate border, white fill, indigo ring when focused.
struct LugiFieldBox<Field: View>: View {
    let label: String
    var focused = false
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.heebo(13, 700)).foregroundStyle(Theme.slate600)
            field()
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(focused ? Theme.brand500 : Theme.slate300, lineWidth: focused ? 2 : 1)
                )
        }
    }
}

/// An empty or error state: Lugi, a title, a line of help and an optional action.
struct EmptyState: View {
    let pose: LugiPose
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Lugi(pose: pose, height: 120)
            Text(title).font(.heebo(19, 800)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.heebo(15, 500)).foregroundStyle(Theme.slate500).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(SoftButtonStyle()).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 26)
    }
}

/// Tab bar in the site's colors (white bar, indigo selection, Heebo labels).
enum AppAppearance {
    static func configure() {
        let item = UITabBarItemAppearance()
        let normal = UIColor(Theme.slate400), selected = UIColor(Theme.brand600)
        item.normal.iconColor = normal
        item.normal.titleTextAttributes = [.font: Heebo.uiFont(11, 600), .foregroundColor: normal]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.font: Heebo.uiFont(11, 700), .foregroundColor: selected]

        let bar = UITabBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = .white
        bar.shadowColor = UIColor(Theme.slate200)
        bar.stackedLayoutAppearance = item
        bar.inlineLayoutAppearance = item
        bar.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
    }
}
