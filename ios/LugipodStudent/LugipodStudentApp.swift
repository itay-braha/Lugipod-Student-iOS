import SwiftUI

@main
struct LugipodStudentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore.shared
    @StateObject private var router = AppRouter()
    @StateObject private var call = CallManager()

    init() { AppAppearance.configure() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(router)
                .environmentObject(call)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .preferredColorScheme(.light)
                .tint(Theme.brand600)
                .onAppear { PushNotifications.shared.router = router }
        }
    }
}
