import SwiftUI

/// The short welcome tour: Lugi the fox shows what the app is for, in a few cards, and then asks for the one thing that matters most, an adult's
/// WhatsApp number. Skippable at any moment; shown once after the first sign-in, and again from "עוד" > "סיור היכרות".
/// Plain information only: nothing here is a price, a plan or a payment prompt (App Store 3.1.3(f)).
struct TourView: View {
    /// The family already has a parent (or another adult's number): the last card is then just "let's go".
    let hasParent: Bool
    /// Called when the tour ends for any reason (finished or skipped); `linkedParent` is true if a number was saved here.
    let onDone: (_ linkedParent: Bool) -> Void

    @State private var page: Int
    @State private var linked = false

    init(hasParent: Bool, startPage: Int = 0, onDone: @escaping (_ linkedParent: Bool) -> Void) {
        self.hasParent = hasParent
        self.onDone = onDone
        _page = State(initialValue: startPage)
    }

    private struct Card: Identifiable {
        let id: Int
        let pose: LugiPose
        let title: String
        let text: String
        let chips: [(String, String)]
        var isParent = false
    }

    private var cards: [Card] {
        var list: [Card] = [
            Card(id: 0, pose: .wave, title: "היי, אני לוגי! 🦊", text: "אני השועל שילווה אתכם בלימודים. סיור קצר ואתם בפנים.", chips: []),
            Card(id: 1, pose: .study, title: "הקבוצות שלכם", text: "השיעורים עם המורה, שיעורי הבית והסיכומים, הכל במקום אחד. עשר דקות לפני כל שיעור תקבלו תזכורת, ואפשר להיכנס ישר לשיעור.",
                 chips: [("person.3.fill", "קבוצה"), ("video.fill", "שיעור חי"), ("doc.text.fill", "סיכומים")]),
            Card(id: 2, pose: .wink, title: "תקועים? שואלים אותי", text: "צלמו שאלה ב־לוגיצ׳אט ואסביר צעד אחר צעד. ובתרגול מחכה אתגר יומי קצר שבונה רצף ונקודות.",
                 chips: [("sparkles", "לוגיצ׳אט"), ("flame.fill", "אתגר יומי"), ("star.fill", "נקודות")]),
            Card(id: 3, pose: .cheer, title: "לומדים עם חברים", text: "מוסיפים חברים, מתחרים על רצף ומקבלים תארים ומסגרות. הזמינו חבר וקבלו לוגי במתנה.",
                 chips: [("person.2.fill", "חברים"), ("trophy.fill", "תארים"), ("gift.fill", "מתנות")]),
        ]
        if !hasParent {
            list.append(Card(id: 4, pose: .sit, title: "הכי חשוב: חברו הורה 👨‍👩‍👧", text: "ההורה (או מבוגר אחר) יקבל הודעת וואטסאפ עם עדכונים על השיעורים. מספר אחד מספיק, וההורה לא צריך להירשם לשום דבר.", chips: [], isParent: true))
        }
        return list
    }

    private var last: Bool { page >= cards.count - 1 }

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 0) {
                topBar
                TabView(selection: $page) {
                    ForEach(cards) { card in
                        cardView(card).tag(card.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                footer
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            if !last {
                Button("דלג") { onDone(linked) }
                    .font(.heebo(16, 700)).foregroundStyle(Theme.slate600)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .accessibilityIdentifier("tour-skip")
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }

    private func cardView(_ card: Card) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Lugi(pose: card.pose, height: card.isParent ? 170 : 230, breathing: true)
                    .padding(.top, 4)
                Text(card.title).font(.heebo(28, 900)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.text).font(.heebo(17, 500)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                if !card.chips.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(card.chips.enumerated()), id: \.offset) { _, chip in
                            VStack(spacing: 6) {
                                Image(systemName: chip.0).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.brand600)
                                Text(chip.1).font(.heebo(13, 800)).foregroundStyle(Theme.brand800)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.brand200, lineWidth: 1))
                        }
                    }
                    .padding(.top, 4)
                }
                if card.isParent { parentBlock }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    /// The one card that asks for something: the adult's number, right here, no detour.
    @ViewBuilder private var parentBlock: some View {
        if linked {
            Label("מעולה! ההורה מחובר ✓", systemImage: "checkmark.seal.fill")
                .font(.heebo(18, 800)).foregroundStyle(Theme.emerald700)
                .padding(.vertical, 12)
        } else {
            ParentLinkForm { linked = true }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.orange400, lineWidth: 2))
                .shadow(color: Theme.orange600.opacity(0.18), radius: 12, y: 6)
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(cards) { c in
                    Capsule()
                        .fill(c.id == page ? (c.isParent ? Theme.orange500 : Theme.brand600) : Theme.slate300)
                        .frame(width: c.id == page ? 22 : 8, height: 8)
                        .animation(.easeOut(duration: 0.2), value: page)
                }
            }
            if last {
                if linked || hasParent {
                    Button("יאללה, מתחילים") { onDone(linked) }
                        .buttonStyle(CTAButtonStyle())
                        .accessibilityIdentifier("tour-finish")
                } else {
                    Button("אעשה את זה אחר כך") { onDone(linked) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("tour-finish")
                }
            } else {
                Button("הבא") { withAnimation { page += 1 } }
                    .buttonStyle(CTAButtonStyle())
                    .accessibilityIdentifier("tour-next")
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 6)
    }
}
