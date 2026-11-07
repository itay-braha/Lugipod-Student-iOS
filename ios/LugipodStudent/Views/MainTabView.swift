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

/// The student's home data, shared by the tabs (Lugichat needs the subjects and the allowance).
@MainActor
final class HomeModel: ObservableObject {
    @Published private(set) var data: StudentHome?
    @Published private(set) var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            data = try await API.get("/api/native/student/home", as: StudentHome.self)
            error = nil
        } catch APIError.notAStudent {
            await AuthStore.shared.signOut(notice: "החשבון הזה אינו חשבון תלמיד. האפליקציה הזו מיועדת לתלמידים (למורים יש אפליקציה נפרדת).")
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            self.error = "לא הצלחנו לטעון את הנתונים. בדקו חיבור ונסו שוב."
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var inbox = InboxModel()
    @StateObject private var home = HomeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("בית", systemImage: "house.fill") }
                .tag(AppRouter.Tab.home)
            LugichatView()
                .tabItem { Label("לוגיצ׳אט", systemImage: "camera.viewfinder") }
                .tag(AppRouter.Tab.lugichat)
            DailyChallengeView()
                .tabItem { Label("תרגול", systemImage: "flame.fill") }
                .tag(AppRouter.Tab.practice)
            MoreView()
                .tabItem { Label("עוד", systemImage: "ellipsis.circle.fill") }
                .tag(AppRouter.Tab.more)
        }
        .tint(Theme.brand600)
        .environmentObject(inbox)
        .environmentObject(home)
        .task {
            await inbox.load()
            await home.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await inbox.load(); await home.load() } }
        }
        .sheet(isPresented: $router.showAlerts) {
            AlertsView()
                .environmentObject(inbox)
                .environmentObject(router)
                .environment(\.layoutDirection, .rightToLeft)
                .presentationDragIndicator(.visible)
        }
    }
}
