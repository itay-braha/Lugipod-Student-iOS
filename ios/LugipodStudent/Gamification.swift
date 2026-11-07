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
    @Published private(set) var coins: Coins?

    /// The fox jumps in with a short cheer. Gone by itself after about two seconds, never in the way.
    func fox(_ title: String, subtitle: String? = nil, pose: LugiPose = .praise, big: Bool = false) {
        let item = Fox(title: title, subtitle: subtitle, pose: pose, big: big)
        fox = item
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
