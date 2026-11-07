import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            switch auth.state {
            case .loading: LoadingView()
            case .notConfigured: SetupMissingView()
            case .signedOut: LoginView()
            case .signedIn: MainTabView()
            }
        }
        .fullScreenCover(item: $router.web) { target in
            WebScreen(path: target.path)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .task(id: auth.state) {
            #if DEBUG
            if PreviewMode.isOn { return }
            #endif
            guard auth.state == .signedIn else { return }
            await PushNotifications.shared.requestAuthorizationAndRegister()
            await PushNotifications.shared.uploadIfPossible()
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 16) {
                Lugi(pose: .walk, height: 130)
                Wordmark(size: 28)
                ProgressView()
            }
        }
    }
}

struct SetupMissingView: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            EmptyState(pose: .peek, title: "האפליקציה לא הוגדרה",
                       message: "חסרים פרטי החיבור לשרת (Secrets.xcconfig). ראו את ה-README.")
                .frame(maxWidth: 460).padding(20)
        }
    }
}
