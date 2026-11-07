import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var call: CallManager

    var body: some View {
        #if DEBUG
        if PreviewMode.screen == "call" {
            // Screenshots only: the lesson screen with a sample room (no network, no video).
            LessonCallScreen(path: "/meeting/lesson/preview")
                .environment(\.layoutDirection, .rightToLeft)
                .task { call.loadPreview() }
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        ZStack {
            switch auth.state {
            case .loading: LoadingView()
            case .notConfigured: SetupMissingView()
            case .signedOut: LoginView()
            case .signedIn: MainTabView()
            }
        }
        .fullScreenCover(item: $router.web) { target in
            Group {
                // The lesson room: native video on top, the lesson page below as the controls.
                if target.path.hasPrefix("/meeting") {
                    LessonCallScreen(path: target.path)
                } else {
                    WebScreen(path: target.path)
                }
            }
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
