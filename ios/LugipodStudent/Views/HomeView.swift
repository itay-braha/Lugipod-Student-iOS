import SwiftUI

/// Where the Home tab can go.
enum HomeRoute: Hashable {
    case group(String)
    case allGroups
    case pastLessons
}

/// Home: a bold indigo header with who you are, what you have consumed (the gold fox coin and the number), and the streak; then the lessons.
/// Groups come first, ordered by whichever lesson is soonest, each one a coloured card with the teacher, who is in it, the next lesson, the
/// homework and the two actions that matter (ask the teacher, look back). Lugichat and the daily challenge live in the tab bar.
struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var inbox: InboxModel
    @EnvironmentObject private var model: HomeModel
    @State private var path: [HomeRoute] = []
    @State private var askGroup: StudentHome.Group?
    @State private var showParent = false
    @State private var upgrade: Upgrade = .idle
    @State private var showProfile = false
    @State private var showRewards = false

    private let shownGroups = 3

    private enum Upgrade: Equatable { case idle, sending, sent, failed(String) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    VStack(spacing: 18) {
                        attention
                        content
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 36)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .background(ScreenBackground())
            .refreshable { await model.load(); await inbox.load() }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .group(let id): GroupDetailView(groupId: id)
                case .allGroups: AllGroupsView(path: $path)
                case .pastLessons: PastLessonsView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $askGroup) { group in
            AskTeacherSheet(group: group) { Task { await model.load() } }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet { Task { await model.load() } }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showRewards) {
            RewardsSheet().presentationDetents([.large]).presentationDragIndicator(.visible).environment(\.layoutDirection, .rightToLeft)
        }
        // The reminder alert / push "link a parent" lands here. Nothing to do if an adult is already linked.
        .onChange(of: router.showParentLink) { _, wanted in
            guard wanted else { return }
            router.showParentLink = false
            if model.data?.family.hasParent != true { showParent = true }
        }
        .onAppear {
            if router.showParentLink {
                router.showParentLink = false
                if model.data?.family.hasParent != true { showParent = true }
            }
        }
        .sheet(isPresented: $showParent) {
            ParentSheet { Task { await model.load() } }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
        }
        #if DEBUG
        .onChange(of: model.data) { _, data in
            // Screenshots only: open the group screen / the ask sheet once the sample data is in.
            if (PreviewMode.screen == "group" || ProcessInfo.processInfo.environment["LUGIPOD_GROUP"] == "1"), path.isEmpty, let id = data?.groups.first?.id { path = [.group(id)] }
            if PreviewMode.screen == "ask", askGroup == nil { askGroup = data?.groups.first }
        }
        #endif
    }

    // MARK: Hero

    private var firstName: String {
        model.data?.student.name.split(separator: " ").first.map(String.init) ?? ""
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            topRow
            consumptionRow
            if let c = model.data?.consumption, c.limitReached == true { limitBanner }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, ScreenInsets.top + 12).padding(.bottom, 26)
        .frame(maxWidth: .infinity)
        .background {
            // The indigo block runs up under the status bar; its content stays below it.
            ZStack {
                Theme.hero
                // a warm glow in the corner, the fox's orange
                RadialGradient(colors: [Theme.orange500.opacity(0.55), Theme.orange500.opacity(0)], center: .bottomLeading, startRadius: 0, endRadius: 320)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous))
            .shadow(color: Theme.brand800.opacity(0.35), radius: 16, y: 8)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { showProfile = true } label: {
                AvatarView(name: model.data?.student.name ?? "", avatar: model.data?.badge?.avatar, frame: model.data?.badge?.frame, size: 58)
                    .overlay(RoundedRectangle(cornerRadius: 58 * 0.32, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 2.5))
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "chevron.down.circle.fill").font(.system(size: 17)).foregroundStyle(.white, Theme.orange500).offset(x: -5, y: 5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("הפרופיל שלי: תארים, רצף ונקודות")
            VStack(alignment: .leading, spacing: 5) {
                Text(firstName.isEmpty ? "שלום" : "שלום, \(firstName)").font(.heebo(23, 900)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    if let title = model.data?.badge?.title { TitleChip(title: title) }
                    if let level = model.data?.points?.level {
                        Text("⚡ \(level)").font(.heebo(12, 800)).foregroundStyle(.white)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 3).background(Color.white.opacity(0.2), in: Capsule())
                    }
                }
            }
            Spacer(minLength: 8)
            Button { router.showAlerts = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.2), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    if inbox.unread > 0 {
                        Text("\(min(inbox.unread, 9))").font(.heebo(11, 900)).foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18).background(Theme.orange500, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(inbox.unread > 0 ? "התראות, \(inbox.unread) חדשות" : "התראות")
        }
    }

    /// This student's own consumption: the gold fox coin and the number (the number ticks up, with coins, when lugis are spent), the streak, and
    /// how much of their own share is used when they have one. Never the family's numbers.
    private var consumptionRow: some View {
        let c = model.data?.consumption
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                CoinCounter(value: c?.consumedLugis ?? 0, capLugis: c?.uncapped == false ? c?.capLugis : nil)
                Spacer(minLength: 8)
                if let streak = model.data?.dailyChallenge.streak, streak > 0 {
                    Button { showRewards = true } label: {
                        VStack(spacing: 0) {
                            Text("🔥").font(.system(size: 22))
                            Text("\(streak)").font(.heebo(20, 900)).foregroundStyle(.white)
                            Text("עוד \(model.data?.dailyChallenge.toGift ?? 10) ללוגי 🪙").font(.heebo(10, 800)).foregroundStyle(.white.opacity(0.95)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 74, height: 76)
                        .background(Theme.cta, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Theme.orange700.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("רצף של \(streak) ימים. אפשר ללמוד איך מרוויחים")
                }
            }
            if let gift = c?.giftLugis, gift > 0 { giftStrip(gift) }
            if let c, c.uncapped == false, let cap = c.capLugis, cap > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule().fill(c.limitReached == true ? AnyShapeStyle(Theme.orange500) : AnyShapeStyle(Theme.coin))
                            .frame(width: max(8, geo.size.width * min(1, c.consumedLugis / cap)))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    /// Earned lugis waiting to be used: shown next to what was used, they go down by themselves with every lesson, and the strip is gone
    /// once they are (then the home is exactly as it was before). Lugis only, never a shekel amount.
    private func giftStrip(_ gift: Double) -> some View {
        HStack(spacing: 10) {
            Text("🎁").font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(gift == gift.rounded() ? String(Int(gift)) : String(format: "%.1f", gift)) לוגי במתנה").font(.heebo(17, 900)).foregroundStyle(Theme.gold300)
                Text("יורדים לבד מכל שיעור שלומדים. כשנגמרים, חוזרים לרגיל.").font(.heebo(12, 700)).foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.gold300.opacity(0.6), lineWidth: 1.2))
        .accessibilityElement(children: .combine)
    }

    /// The student reached their own monthly limit: say so plainly and offer the one thing they can do, let the parent know. That sends the
    /// parent OUR WhatsApp message with the exact situation and an approval link: a message to a person, not a purchase in the app.
    private var limitBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("הגעת למגבלה החודשית שלך", systemImage: "exclamationmark.circle.fill")
                .font(.heebo(16, 900)).foregroundStyle(.white)
            Text("כדי להמשיך לקבוע שיעורים ופעילויות, ההורה צריך לדעת על זה.").font(.heebo(14, 600)).foregroundStyle(.white.opacity(0.92))
            switch upgrade {
            case .sent:
                Label("שלחנו להורה הודעה עם כל הפרטים ✓", systemImage: "checkmark.circle.fill")
                    .font(.heebo(14, 800)).foregroundStyle(Theme.gold300)
            case .failed(let message):
                Text(message).font(.heebo(13, 700)).foregroundStyle(Theme.gold300)
                letParentKnowButton
            default:
                letParentKnowButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.orange400.opacity(0.7), lineWidth: 1.5))
    }

    private var letParentKnowButton: some View {
        Button { Task { await tellParent() } } label: {
            HStack(spacing: 8) { if upgrade == .sending { ProgressView().tint(.white) }; Image(systemName: "paperplane.fill"); Text("עדכנו את ההורה") }
        }
        .buttonStyle(CTAButtonStyle())
        .disabled(upgrade == .sending)
    }

    private func tellParent() async {
        guard model.data?.family.hasParent == true else { showParent = true; return }
        upgrade = .sending
        do {
            _ = try await API.request("POST", "/api/native/student/cap-request", json: [:], timeout: 30)
            upgrade = .sent
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch APIError.server(_, let message) where !message.isEmpty {
            upgrade = .failed(message)
        } catch { upgrade = .failed("לא הצלחנו לשלוח. בדקו חיבור ונסו שוב.") }
    }

    /// The newest unread alert, as one line: the app points at what is relevant instead of hiding it behind a bell.
    @ViewBuilder private var attention: some View {
        if let a = inbox.alerts.first(where: \.isUnread) {
            Button {
                Task { await inbox.markRead([a.id]) }
                router.open(path: a.path)
            } label: {
                HStack(spacing: 10) {
                    Text(a.emoji ?? "🔔").font(.system(size: 22))
                    Text(a.title).font(.heebo(15, 800)).foregroundStyle(Theme.brand800).lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.brand500)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.brand200, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let data = model.data {
            if let offer = model.encore { EncoreCardView(rebook: offer) { Task { await model.load() } } }
            groupsSection(data.groups)
            parentCard(data)
            libraryTile
        } else if let error = model.error {
            EmptyState(pose: .peek, title: "משהו לא נטען", message: error, actionTitle: "נסו שוב") { Task { await model.load() } }
        } else {
            // First ever open: the shape of what is coming, not a spinner.
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.7)).frame(height: 230)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func groupsSection(_ groups: [StudentHome.Group]) -> some View {
        VStack(spacing: 14) {
            SectionTitle(text: "הקבוצות שלי", count: groups.count)
            if groups.isEmpty {
                EmptyState(pose: .sit, title: "עדיין אין קבוצה", message: "כשתשובצו לקבוצה, השיעורים שלכם יופיעו כאן.")
            } else {
                ForEach(groups.prefix(shownGroups)) { g in
                    GroupCard(group: g,
                              onAsk: { askGroup = g },
                              onJoin: { router.open(path: "/meeting/lesson/\($0)") },
                              onHomework: { path.append(.group(g.id)) })
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(.group(g.id)) }
                }
                if groups.count > shownGroups {
                    Button { path.append(.allGroups) } label: {
                        HStack { Text("כל הקבוצות (\(groups.count))"); Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: Parent and library

    @ViewBuilder
    private func parentCard(_ data: StudentHome) -> some View {
        if data.family.hasParent {
            Label("מחוברים להורה ✓", systemImage: "checkmark.seal.fill").font(.heebo(14, 800)).foregroundStyle(Theme.emerald700)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("👨‍👩‍👧").font(.system(size: 26))
                    Text("חברו הורה").font(.heebo(18, 900)).foregroundStyle(.white)
                }
                Text("ההורה מקבל עדכונים על השיעורים ורואה מה נוצל.").font(.heebo(14, 600)).foregroundStyle(.white.opacity(0.92))
                Button { showParent = true } label: { Label("חיבור הורה", systemImage: "person.badge.plus") }
                    .buttonStyle(SoftButtonStyle(fg: Theme.brand800, bg: .white))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.hero, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.brand700.opacity(0.3), radius: 10, y: 5)
        }
    }

    private var libraryTile: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.slate500)
            Text("ספריית הסרטונים").font(.heebo(15, 800)).foregroundStyle(Theme.slate700)
            Text("בקרוב").font(.heebo(12, 800)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 3).background(Theme.orange500, in: Capsule())
            Spacer()
        }
        .padding(14)
        .background(Theme.slate100, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
