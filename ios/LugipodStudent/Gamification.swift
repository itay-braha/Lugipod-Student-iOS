import SwiftUI
import UIKit

// MARK: - Avatar and title (the website's UserBadge, natively)

private let animals = ["🦁", "🐼", "🦊", "🐨", "🐯", "🐧", "🦄", "🐸", "🐵", "🐶", "🐱", "🐰", "🐻", "🦝", "🐺", "🐮"]
private let gradients: [[Color]] = [
    [Color(hex: 0xA78BFA), Color(hex: 0xE879F9)], [Color(hex: 0x34D399), Color(hex: 0x2DD4BF)],
    [Color(hex: 0xFB7185), Color(hex: 0xFB923C)], [Color(hex: 0x38BDF8), Color(hex: 0x818CF8)],
    [Color(hex: 0xFBBF24), Color(hex: 0xFDE047)], [Color(hex: 0xF472B6), Color(hex: 0xFB7185)],
    [Color(hex: 0x22D3EE), Color(hex: 0x60A5FA)], [Color(hex: 0xA3E635), Color(hex: 0x34D399)],
]

private func nameHash(_ name: String) -> Int {
    var h = 0
    for u in name.unicodeScalars { h = (h + Int(u.value)) % 9973 }
    return h
}

/// The student's avatar: their equipped emoji, or a stable animal on a gradient chosen from their name; a ring when a frame is equipped.
struct AvatarView: View {
    let name: String
    var avatar: String?
    var frame: String?
    var size: CGFloat = 52

    var body: some View {
        let h = nameHash(name)
        let g = gradients[h % gradients.count]
        Text(avatar ?? animals[h % animals.count])
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(LinearGradient(colors: g, startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .overlay {
                if let ring = ringColor {
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).strokeBorder(ring, lineWidth: 3)
                }
            }
            .shadow(color: (frame != nil ? ringColor : nil)?.opacity(0.35) ?? Theme.shadowSoft2, radius: 6, y: 3)
            .accessibilityHidden(true)
    }

    private var ringColor: Color? {
        switch frame {
        case "frame_violet": return Theme.violet500
        case "frame_gold": return Theme.amber400
        default: return nil
        }
    }
}

/// The title the student earned, as a chip coloured by rarity.
struct TitleChip: View {
    let title: StudentHome.Badge.Title

    var body: some View {
        let (fg, bg): (Color, AnyShapeStyle) = {
            switch title.rarity {
            case "rare": return (Theme.sky800, AnyShapeStyle(Color(hex: 0xE0F2FE)))
            case "epic": return (Theme.violet700, AnyShapeStyle(Theme.violet50))
            case "legendary": return (Color(hex: 0xA21CAF), AnyShapeStyle(LinearGradient(colors: [Theme.amber100, Color(hex: 0xFAE8FF)], startPoint: .leading, endPoint: .trailing)))
            default: return (Theme.amber800, AnyShapeStyle(Theme.amber100))
            }
        }()
        Text("\(title.emoji) \(title.label)")
            .font(.heebo(12, 800)).foregroundStyle(fg)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(bg, in: Capsule())
    }
}

// MARK: - Celebrations: the fox, and coins

/// What the host should show next. Fired from anywhere (`celebration.fox(...)`, `celebration.coins(...)`).
@MainActor
final class CelebrationCenter: ObservableObject {
    struct Fox: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let pose: LugiPose
        let big: Bool
    }
    struct Coins: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var fox: Fox?
    private var poseTurn = Int.random(in: 0..<10)
    @Published private(set) var coins: Coins?

    /// The fox jumps in with a short cheer. Gone by itself after about two seconds, never in the way.
    /// Pass `pose: nil` and a different one is picked each time, so the same fox does not greet every right answer.
    func fox(_ title: String, subtitle: String? = nil, pose: LugiPose? = nil, big: Bool = false) {
        let pool: [LugiPose] = big ? [.cheer, .joy, .party, .leap, .proud, .praise] : [.praise, .joy, .wink, .leap, .proud, .cheer, .walk]
        poseTurn += 1
        let item = Fox(title: title, subtitle: subtitle, pose: pose ?? pool[poseTurn % pool.count], big: big)
        fox = item
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #if DEBUG
        if PreviewMode.isOn { return }   // screenshots: leave it on screen
        #endif
        Task {
            try? await Task.sleep(nanoseconds: big ? 2_800_000_000 : 1_900_000_000)
            if fox?.id == item.id { fox = nil }
        }
    }

    /// A few coins float up with the amount, when lugis are spent.
    func coins(_ text: String) {
        let item = Coins(text: text)
        coins = item
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if coins?.id == item.id { coins = nil }
        }
    }
}

/// Draws the celebrations over the whole app. Touches pass straight through it.
struct CelebrationHost: View {
    @ObservedObject var center: CelebrationCenter

    var body: some View {
        ZStack {
            if let fox = center.fox { FoxBurst(fox: fox).id(fox.id).transition(.opacity) }
            if let coins = center.coins { CoinBurst(text: coins.text).id(coins.id).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.25), value: center.fox)
        .animation(.easeOut(duration: 0.25), value: center.coins)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct FoxBurst: View {
    let fox: CelebrationCenter.Fox
    @State private var shown = false
    @State private var confetti = false

    private let pieces = ["🎉", "✨", "⭐", "🎊", "💛", "💜", "✨", "🎉"]

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.18 : 0)
            // confetti
            ForEach(Array(pieces.enumerated()), id: \.offset) { i, p in
                Text(p).font(.system(size: fox.big ? 30 : 22))
                    .offset(x: confetti ? CGFloat(cos(Double(i) / 8 * 2 * .pi)) * (fox.big ? 150 : 110) : 0,
                            y: confetti ? CGFloat(sin(Double(i) / 8 * 2 * .pi)) * (fox.big ? 150 : 110) - 40 : 40)
                    .opacity(confetti ? 0.0 : 1)
                    .animation(.easeOut(duration: 1.3).delay(Double(i) * 0.03), value: confetti)
            }
            VStack(spacing: 6) {
                Lugi(pose: fox.pose, height: fox.big ? 210 : 150)
                    .scaleEffect(shown ? 1 : 0.3)
                    .rotationEffect(.degrees(shown ? 0 : -12))
                Text(fox.title).font(.heebo(fox.big ? 28 : 22, 900)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                if let s = fox.subtitle { Text(s).font(.heebo(15, 700)).foregroundStyle(.white.opacity(0.95)).shadow(color: .black.opacity(0.3), radius: 4, y: 1) }
            }
            .offset(y: shown ? 0 : 80)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { shown = true }
            confetti = true
        }
    }
}

private struct CoinBurst: View {
    let text: String
    @State private var rise = false

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    Text("🪙").font(.system(size: 26))
                        .offset(x: CGFloat(i - 2) * 22, y: rise ? -150 - CGFloat(i % 3) * 22 : 0)
                        .opacity(rise ? 0 : 1)
                        .rotationEffect(.degrees(rise ? Double(i - 2) * 40 : 0))
                        .animation(.easeOut(duration: 1.5).delay(Double(i) * 0.08), value: rise)
                }
                Text(text).font(.heebo(17, 900)).foregroundStyle(Theme.amber800)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.amber100, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.amber200, lineWidth: 1))
                    .offset(y: rise ? -190 : -40)
                    .opacity(rise ? 0 : 1)
                    .animation(.easeOut(duration: 1.9), value: rise)
            }
            .padding(.bottom, 140)
        }
        .onAppear { rise = true }
    }
}

// MARK: - The lugi coin

/// The lugi coin with the fox on it: gold for lugis spent, the same coin in BLUE (`awarded`) for lugis given (gifts, a friend's four
/// lessons, streaks). Wherever awarded lugis are shown, they carry the blue coin and their amount.
struct FoxCoin: View {
    var size: CGFloat = 58
    var awarded = false

    var body: some View {
        ZStack {
            Circle().fill(awarded ? Theme.awardedCoin : Theme.coin)
            Circle().strokeBorder(Color(hex: awarded ? 0x1E3A8A : 0xB45309).opacity(0.55), lineWidth: size * 0.05)
            Circle().strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: size * 0.02, dash: [size * 0.06, size * 0.05])).padding(size * 0.1)
            Image("Lugi-peek").resizable().scaledToFill()
                .frame(width: size * 0.66, height: size * 0.66)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .shadow(color: (awarded ? Color(hex: 0x1E40AF) : Theme.gold700).opacity(0.45), radius: size * 0.12, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

/// What THIS student has consumed this month: the gold coin with the fox, and the number next to it. When lugis are spent the number ticks up,
/// pops, and a few coins fly off the coin. (Only the student's own usage ever appears here, never the family's.)
struct CoinCounter: View {
    let value: Double
    var capLugis: Double?
    var onDark = true
    @State private var pop = false
    @State private var fly = false
    @State private var delta: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                FoxCoin(size: 62).scaleEffect(pop ? 1.18 : 1).rotationEffect(.degrees(pop ? -8 : 0))
                ForEach(0..<4, id: \.self) { i in
                    Text("🪙").font(.system(size: 16))
                        .offset(x: CGFloat(i - 2) * 14 + 7, y: fly ? -56 - CGFloat(i % 2) * 14 : 0)
                        .opacity(fly ? 0 : 0.001)
                        .animation(.easeOut(duration: 1.0).delay(Double(i) * 0.07), value: fly)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(format(value)).font(.heebo(34, 900)).foregroundStyle(onDark ? .white : Theme.ink)
                        .contentTransition(.numericText(value: value))
                        .scaleEffect(pop ? 1.12 : 1, anchor: .leading)
                    if let cap = capLugis { Text("/ \(format(cap))").font(.heebo(16, 700)).foregroundStyle(onDark ? .white.opacity(0.75) : Theme.slate500) }
                }
                Text("לוגי נוצלו החודש").font(.heebo(13, 700)).foregroundStyle(onDark ? Theme.gold300 : Theme.gold700)
            }
            .overlay(alignment: .topLeading) {
                if pop && delta > 0 {
                    Text("+\(format(delta))").font(.heebo(16, 900)).foregroundStyle(Theme.gold300)
                        .offset(x: 80, y: -22).transition(.opacity)
                }
            }
        }
        .onChange(of: value) { old, new in
            guard new > old + 0.01 else { return }
            delta = new - old
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            fly = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { pop = true }
            DispatchQueue.main.async { fly = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(.easeOut(duration: 0.3)) { pop = false } }
        }
        .animation(.easeOut(duration: 0.6), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("נוצלו \(format(value)) לוגי החודש")
    }

    private func format(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

/// The height of the status bar / Dynamic Island area, so a screen can draw its colour under it and keep its content below it.
enum ScreenInsets {
    static var top: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow?.safeAreaInsets.top ?? 47
    }
}
