import SwiftUI

/// Where the Home tab can go.
enum HomeRoute: Hashable {
    case group(String)
    case allGroups
    case pastLessons
}

/// Home is about the lessons: the groups, ordered by whichever lesson is soonest, each one a card with the teacher, who is in it, the next
/// lesson, the homework and the two actions that matter (ask the teacher, look back). Below them, the family and the month's usage.
/// Lugichat and the daily challenge live in the tab bar, not here.
struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var inbox: InboxModel
    @EnvironmentObject private var model: HomeModel
    @State private var path: [HomeRoute] = []
    @State private var askGroup: StudentHome.Group?
    @State private var showParent = false

    private let shownGroups = 3

    var body: some View {
        NavigationStack(path: $path) {
            Scaffold(maxWidth: 720) {
                header
                attention
                content
            }
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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
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
            if PreviewMode.screen == "group", path.isEmpty, let id = data?.groups.first?.id { path = [.group(id)] }
            if PreviewMode.screen == "ask", askGroup == nil { askGroup = data?.groups.first }
        }
        #endif
    }

    // MARK: Header

    private var firstName: String {
        model.data?.student.name.split(separator: " ").first.map(String.init) ?? ""
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(HebrewDate.longDay(Date())).font(.heebo(13, 600)).foregroundStyle(Theme.slate500)
                Text(firstName.isEmpty ? "שלום 👋" : "שלום, \(firstName) 👋").font(.heebo(28, 800)).foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 8)
            if let streak = model.data?.dailyChallenge.streak, streak > 0 {
                Pill(text: "🔥 \(streak)", fg: Theme.amber800, bg: Theme.amber100)
            }
            Button { router.showAlerts = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.brand700)
                        .frame(width: 46, height: 46)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.slate200, lineWidth: 1))
                        .shadow(color: Theme.shadowSoft2, radius: 6, y: 3)
                    if inbox.unread > 0 {
                        Text("\(min(inbox.unread, 9))").font(.heebo(11, 800)).foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18).background(Theme.rose500, in: Circle())
                            .offset(x: 3, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(inbox.unread > 0 ? "התראות, \(inbox.unread) חדשות" : "התראות")
        }
        .padding(.top, 4)
    }

    /// The newest unread alert, as one line: the app points at what is relevant instead of hiding it behind a bell.
    @ViewBuilder private var attention: some View {
        if let a = inbox.alerts.first(where: \.isUnread) {
            Button {
                Task { await inbox.markRead([a.id]) }
                router.open(path: a.path)
            } label: {
                HStack(spacing: 10) {
                    Text(a.emoji ?? "🔔").font(.system(size: 20))
                    Text(a.title).font(.heebo(14, 700)).foregroundStyle(Theme.brand800).lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.brand400)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.brand200, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let data = model.data {
            groupsSection(data.groups)
            familyCard(data)
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
        VStack(spacing: 12) {
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
                Button { path.append(.pastLessons) } label: {
                    HStack(spacing: 6) { Image(systemName: "clock.arrow.circlepath"); Text("כל השיעורים הקודמים") }
                }
                .font(.heebo(14, 700)).foregroundStyle(Theme.slate600).padding(.top, 2)
            }
        }
    }

    // MARK: Family and usage

    private func familyCard(_ data: StudentHome) -> some View {
        let c = data.consumption
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("👨‍👩‍👧").font(.system(size: 22))
                Text("המשפחה והצריכה").font(.heebo(18, 800)).foregroundStyle(Theme.ink)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("בחודש הזה").font(.heebo(13, 700)).foregroundStyle(Theme.slate500)
                    Spacer()
                    Text(HebrewDate.monthYear(c.period)).font(.heebo(12, 600)).foregroundStyle(Theme.slate400)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(lugiText(c.consumedLugis)).font(.heebo(30, 800)).foregroundStyle(Theme.brand700)
                    Text("לוגי נוצלו").font(.heebo(15, 600)).foregroundStyle(Theme.slate600)
                    if let cap = c.capLugis {
                        Text("מתוך \(lugiText(cap))").font(.heebo(14, 600)).foregroundStyle(Theme.slate500)
                    }
                }
                if let cap = c.capLugis, cap > 0 {
                    ProgressView(value: min(1, c.consumedLugis / cap))
                        .tint(c.pctUsed >= 85 ? Theme.rose500 : Theme.brand500)
                } else {
                    Text("ללא תקרה חודשית").font(.heebo(13, 500)).foregroundStyle(Theme.slate500)
                }
                if c.creditLugis > 0 {
                    Label("זיכוי שנצבר: \(lugiText(c.creditLugis)) לוגי", systemImage: "gift.fill").font(.heebo(13, 700)).foregroundStyle(Theme.emerald700)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brand50.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if data.family.hasParent {
                Label("מחוברים להורה ✓", systemImage: "checkmark.seal.fill").font(.heebo(14, 700)).foregroundStyle(Theme.emerald700)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("עוד לא חיברתם הורה. ההורה מקבל עדכונים על השיעורים והצריכה ומנהל את התשלום.")
                        .font(.heebo(14, 500)).foregroundStyle(Theme.slate600)
                    Button { showParent = true } label: { Label("חברו הורה", systemImage: "person.badge.plus") }
                        .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.brand600))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }

    private func lugiText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private var libraryTile: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.slate400)
            Text("ספריית הסרטונים").font(.heebo(15, 700)).foregroundStyle(Theme.slate600)
            Text("בקרוב").font(.heebo(12, 700)).foregroundStyle(Theme.amber800)
                .padding(.horizontal, 8).padding(.vertical, 2).background(Theme.amber100, in: Capsule())
            Spacer()
        }
        .padding(14)
        .background(Theme.slate50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
