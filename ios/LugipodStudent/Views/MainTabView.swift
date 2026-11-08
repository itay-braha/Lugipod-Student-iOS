import SwiftUI

/// The bell, as a shared object: the alerts sheet shows it, the home header and the app icon show its count.
@MainActor
final class InboxModel: ObservableObject {
    @Published private(set) var alerts: [AlertItem] = []
    @Published private(set) var unread = 0
    @Published private(set) var loaded = false
    @Published var error: String?

    func load() async {
        do {
            let r = try await API.get("/api/native/alerts", as: AlertsResponse.self)
            alerts = r.alerts
            unread = r.unread
            error = nil
            loaded = true
            PushNotifications.shared.setBadge(r.unread)
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            self.error = "לא הצלחנו לטעון את ההתראות"
        }
    }

    func markRead(_ ids: [String]) async {
        let set = Set(ids)
        let now = Date()
        alerts = alerts.map { a in
            set.contains(a.id) && a.isUnread
                ? AlertItem(id: a.id, type: a.type, title: a.title, body: a.body, emoji: a.emoji, createdAt: a.createdAt, readAt: now, path: a.path)
                : a
        }
        unread = alerts.filter(\.isUnread).count
        PushNotifications.shared.setBadge(unread)
        _ = try? await API.post("/api/native/alerts", json: ["ids": ids])
    }

    func markAllRead() async {
        await markRead(alerts.filter(\.isUnread).map(\.id))
        _ = try? await API.post("/api/native/alerts", json: ["all": true])
    }
}

/// The student's home data, shared by the tabs. It starts from the copy kept on disk, so the screen is never empty on launch.
@MainActor
final class HomeModel: ObservableObject {
    @Published private(set) var data: StudentHome?
    @Published private(set) var loading = false
    @Published var error: String?
    /// An open "same time next week?" offer, if there is one for this student.
    @Published private(set) var encore: ActiveRebook?

    init() {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        if let raw = LocalCache.read("home"), let cached = try? API.decoder.decode(StudentHome.self, from: raw) { data = cached }
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let raw = try await API.request("GET", "/api/native/student/home")
            data = try API.decoder.decode(StudentHome.self, from: raw)
            LocalCache.write("home", raw)
            error = nil
            encore = await Rebook.active()
        } catch APIError.notAStudent {
            await AuthStore.shared.signOut(notice: "החשבון הזה אינו חשבון תלמיד. האפליקציה הזו מיועדת לתלמידים (למורים יש אפליקציה נפרדת).")
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            // Keep showing what we have; only say something when there is nothing to show.
            if data == nil { self.error = "לא הצלחנו לטעון את הנתונים. בדקו חיבור ונסו שוב." }
        }
    }
}

/// The bottom bar: one colour per place, so the app is easy to read at a glance.
struct AppTabBar: View {
    @Binding var selection: AppRouter.Tab

    private struct Item { let tab: AppRouter.Tab; let title: String; let icon: String; let color: Color }
    private let items: [Item] = [
        Item(tab: .home, title: "הקבוצות", icon: "house.fill", color: Theme.brand600),
        Item(tab: .lugichat, title: "לוגיצ׳אט", icon: "sparkles", color: Theme.violet500),
        Item(tab: .practice, title: "תרגול", icon: "flame.fill", color: Theme.orange500),
        Item(tab: .friends, title: "חברים", icon: "person.2.fill", color: Color(hex: 0xEC4899)),
        Item(tab: .more, title: "עוד", icon: "square.grid.2x2.fill", color: Theme.emerald600),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let on = selection == item.tab
                Button { selection = item.tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(on ? .white : item.color)
                            .frame(width: 60, height: 34)
                            .background { if on { Capsule().fill(item.color.gradient).shadow(color: item.color.opacity(0.45), radius: 6, y: 3) } }
                        Text(item.title).font(.heebo(11, on ? 900 : 700)).foregroundStyle(on ? item.color : Theme.slate600)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: 560)
        .padding(.top, 8).padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(Color.white.shadow(.drop(color: Theme.shadowSoft2, radius: 8, y: -2)), ignoresSafeAreaEdges: .bottom)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var inbox = InboxModel()
    @StateObject private var home = HomeModel()
    @StateObject private var daily = DailyModel()
    @StateObject private var chat = LugichatModel()
    @StateObject private var friends = FriendsModel()
    @EnvironmentObject private var celebration: CelebrationCenter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            // Every tab keeps its own state (a half-finished chat, the question you are on) because the models live here, above the switch.
            Group {
                switch router.tab {
                case .home: HomeView()
                case .lugichat: LugichatView()
                case .practice: DailyChallengeView()
                case .friends: FriendsView()
                case .more: MoreView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            AppTabBar(selection: $router.tab)
        }
        .background(ScreenBackground())
        .tint(Theme.brand600)
        .environmentObject(inbox)
        .environmentObject(home)
        .environmentObject(daily)
        .environmentObject(chat)
        .environmentObject(friends)
        .overlay { CelebrationHost(center: celebration) }
        // Lugis were spent (a lesson was charged): a few coins float up, so spending is felt, never silent.
        .onChange(of: home.data?.consumption.consumedLugis) { old, new in
            guard let old, let new, new > old + 0.01, scenePhase == .active else { return }
            let spent = new - old
            celebration.coins("−\(spent == spent.rounded() ? String(Int(spent)) : String(format: "%.1f", spent)) לוגי")
        }
        .task {
            await refresh()
            #if DEBUG
            if PreviewMode.screen == "celebrate" { celebration.fox("כל הכבוד!", subtitle: "שמרת על הרצף · +5 נקודות", pose: .cheer, big: true) }
            if PreviewMode.screen == "coins" { celebration.coins("−2 לוגי") }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .sheet(isPresented: $router.showAlerts) {
            // A small sheet over the home, not a full screen: the bell is a glance, not a place.
            AlertsView()
                .environmentObject(inbox)
                .environmentObject(router)
                .environment(\.layoutDirection, .rightToLeft)
                .presentationDetents([.fraction(0.55), .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Everything the first screens need, fetched at the same time (not one after another).
    private func refresh() async {
        async let a: Void = inbox.load()
        async let h: Void = home.load()
        async let d: Void = daily.loadIfNeeded()
        _ = await (a, h, d)
    }
}
