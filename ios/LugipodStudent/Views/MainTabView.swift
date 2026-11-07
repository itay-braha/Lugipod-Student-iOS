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
        Item(tab: .practice, title: "תרגול", icon: "flame.fill", color: Theme.amber500),
        Item(tab: .more, title: "עוד", icon: "square.grid.2x2.fill", color: Theme.emerald600),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let on = selection == item.tab
                Button { selection = item.tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(on ? item.color : item.color.opacity(0.55))
                            .frame(width: 58, height: 32)
                            .background(on ? item.color.opacity(0.14) : .clear, in: Capsule())
                        Text(item.title).font(.heebo(11, on ? 800 : 600)).foregroundStyle(on ? item.color : Theme.slate500)
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            // Every tab keeps its own state (a half-finished chat, the question you are on) because the models live here, above the switch.
            Group {
                switch router.tab {
                case .home: HomeView()
                case .lugichat: LugichatView()
                case .practice: DailyChallengeView()
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
        .task { await refresh() }
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
