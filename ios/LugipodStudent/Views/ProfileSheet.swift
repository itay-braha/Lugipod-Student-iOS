import SwiftUI

@MainActor
final class ProfileModel: ObservableObject {
    @Published private(set) var data: ProfileResponse?
    @Published var error: String?
    @Published private(set) var busyId: String?

    func load() async {
        do {
            let raw = try await API.request("GET", "/api/native/student/profile")
            data = try API.decoder.decode(ProfileResponse.self, from: raw)
            error = nil
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            if data == nil { self.error = "לא הצלחנו לטעון את הפרופיל." }
        }
    }

    /// Puts a title / avatar / frame on (or takes it off when it is already on).
    func toggle(_ item: ProfileResponse.Item) async -> Bool {
        busyId = item.id
        defer { busyId = nil }
        let body: [String: Any] = item.equipped ? ["clear": item.kind] : ["id": item.id]
        do {
            _ = try await API.request("POST", "/api/native/student/profile", json: body)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
            return true
        } catch APIError.server(_, let message) where !message.isEmpty {
            error = message
            return false
        } catch { self.error = "לא הצלחנו. נסו שוב."; return false }
    }
}

/// Tap your avatar: who you are, your streaks and points, and every title, avatar and frame there is: the ones you have (tap to wear one) and the
/// ones still to earn, each with what it takes. Opens "how do I earn" too.
struct ProfileSheet: View {
    var onChanged: () -> Void
    @StateObject private var model = ProfileModel()
    @State private var showRewards = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let d = model.data { content(d) }
                else if let e = model.error { Text(e).font(.heebo(15, 700)).foregroundStyle(Theme.rose600).padding(.top, 60) }
                else { ProgressView().padding(.top, 80) }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20).padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background(ScreenBackground())
        .task { await model.load() }
        .sheet(isPresented: $showRewards) {
            RewardsSheet().presentationDetents([.large]).presentationDragIndicator(.visible).environment(\.layoutDirection, .rightToLeft)
        }
    }

    @ViewBuilder
    private func content(_ d: ProfileResponse) -> some View {
        // who you are
        VStack(spacing: 10) {
            AvatarView(name: d.me.name, avatar: d.me.avatar, frame: d.me.frame, size: 96)
            Text(d.me.name).font(.heebo(28, 900)).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                if let t = d.me.title { TitleChip(title: t) }
                if let p = d.points { Pill(text: "⚡ \(p.level)", fg: Theme.brand700, bg: Theme.brand100) }
            }
        }
        // numbers
        HStack(spacing: 10) {
            tile("🔥", "\(d.me.streak)", "רצף כרגע", Theme.orange600, Theme.orange100)
            tile("⭐", "\(d.me.highestStreak)", "שיא רצף", Theme.amber800, Theme.amber100)
            tile("🏅", "\(d.me.points)", "נקודות", Theme.brand700, Theme.brand100)
        }
        if let p = d.points, let next = p.nextLevelAt, next > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("עוד \(max(0, next - p.lifetime)) נקודות לרמה הבאה").font(.heebo(13, 800)).foregroundStyle(Theme.slate600)
                ProgressView(value: min(1, Double(p.lifetime) / Double(next))).tint(Theme.orange500)
            }
            .card(padding: 14, radius: 18)
        }
        Button { showRewards = true } label: { Label("איך מרוויחים לוגי ונקודות?", systemImage: "questionmark.circle.fill") }
            .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.orange500))

        // the collection
        ForEach([("title", "התארים שלי"), ("avatar", "אווטארים"), ("frame", "מסגרות")], id: \.0) { kind, heading in
            let items = d.items.filter { $0.kind == kind }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: heading, count: items.filter(\.unlocked).count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(items) { item in cell(item) }
                    }
                }
            }
        }
        if let e = model.error { Text(e).font(.heebo(13, 700)).foregroundStyle(Theme.rose600) }
    }

    private func tile(_ icon: String, _ value: String, _ label: String, _ fg: Color, _ bg: Color) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.system(size: 22))
            Text(value).font(.heebo(24, 900)).foregroundStyle(fg)
            Text(label).font(.heebo(11, 800)).foregroundStyle(fg.opacity(0.85))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// A title / avatar / frame: open ones are tappable (a check shows the one you wear); locked ones are dimmed and say what it takes.
    private func cell(_ item: ProfileResponse.Item) -> some View {
        Button {
            guard item.unlocked else { return }
            Task { if await model.toggle(item) { onChanged() } }
        } label: {
            HStack(spacing: 10) {
                Text(item.emoji).font(.system(size: 26)).grayscale(item.unlocked ? 0 : 1).opacity(item.unlocked ? 1 : 0.55)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).font(.heebo(14, 800)).foregroundStyle(item.unlocked ? Theme.ink : Theme.slate500).lineLimit(1)
                    Text(item.unlocked ? (item.equipped ? "עליכם עכשיו ✓" : "לחצו כדי ללבוש") : item.hint)
                        .font(.heebo(11, 700)).foregroundStyle(item.equipped ? Theme.emerald700 : (item.unlocked ? Theme.brand600 : Theme.slate400)).lineLimit(2)
                }
                Spacer(minLength: 0)
                if model.busyId == item.id { ProgressView() }
                else if !item.unlocked { Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.slate400) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(item.equipped ? Theme.emerald50 : (item.unlocked ? Color.white : Theme.slate100), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(item.equipped ? Theme.emerald500 : (item.unlocked ? Theme.brand200 : Theme.slate200), lineWidth: item.equipped ? 2.5 : 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// How lugis and points are earned: the one explanation the student gets, reachable from the daily challenge and from their profile.
struct RewardsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    FoxCoin(size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("איך מרוויחים?").font(.heebo(26, 900)).foregroundStyle(Theme.ink)
                        Text("לימוד קבוע משתלם, ממש").font(.heebo(14, 700)).foregroundStyle(Theme.slate600)
                    }
                    Spacer()
                }
                rule("🔥", "אתגר יומי", "כל 10 ימים ברצף של אתגר יומי = לוגי במתנה. לוגי במתנה פירושו שתשלמו לוגי אחד פחות, והוא תקף לשנה.", Theme.orange100, Theme.orange600)
                rule("📝", "שיעורי בית", "כל תשובה נכונה בשיעורי בית מזכה בנקודות, ובונוס קטן על סיום כל הסט.", Theme.brand100, Theme.brand700)
                rule("🏅", "נקודות הופכות לתארים", "ככל שצוברים נקודות נפתחים תארים (מתחיל/ה, להט, חרוץ/ה, גאון/ית, אלוף/ה, אגדה), אווטארים ומסגרות. אפשר ללבוש אותם בפרופיל, והחברים והקבוצה רואים אותם.", Theme.amber100, Theme.amber800)
                rule("🤝", "חברים", "מזמינים חברים, מתחרים על רצף ונקודות, ולומדים יחד. כשחבר שהזמנתם מסיים 4 שיעורים מלאים, מקבלים 10 לוגי במתנה*. * אם החבר נהנה מהנחה במסגרת ארגון או בית ספר, הסכום יותאם בהתאם.", Color(hex: 0xFCE7F3), Color(hex: 0xBE185D))
                Button("הבנתי") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.top, 4)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20).padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background(ScreenBackground())
    }

    private func rule(_ icon: String, _ title: String, _ text: String, _ bg: Color, _ fg: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon).font(.system(size: 28)).frame(width: 52, height: 52).background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.heebo(17, 900)).foregroundStyle(fg)
                Text(text).font(.heebo(14, 600)).foregroundStyle(Theme.slate700).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 22)
    }
}
