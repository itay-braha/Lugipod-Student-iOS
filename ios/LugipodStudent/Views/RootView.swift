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
        } else if PreviewMode.screen?.hasPrefix("tour") == true {
            // Screenshots only: the welcome tour on its own (tour-0 ... tour-3, tour-parent = the card that asks for a parent's number).
            TourViewPreview()
        } else if PreviewMode.screen == "invite" {
            // Screenshots only: the invite sheet on its own.
            InviteSheet(invite: .init(link: "https://lugipod.com/r/2ebe1b55", text: "")).environment(\.layoutDirection, .rightToLeft)
        } else if PreviewMode.screen == "friends-list" {
            // Screenshots only: the friends tab without the tab shell.
            FriendsView().environmentObject(FriendsModel()).environment(\.layoutDirection, .rightToLeft)
        } else if PreviewMode.screen?.hasPrefix("post-lesson") == true {
            // Screenshots only: the "how was it?" flow with the next-lesson offer.
            PostLessonFlow(kind: "lesson", ref: "preview", leftEarly: false, teacherName: "איתי") {}
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
            if PreviewMode.isOn || AuthStore.autologin != nil { return }   // screenshots never ask for notification permission
            #endif
            guard auth.state == .signedIn else { return }
            await PushNotifications.shared.requestAuthorizationAndRegister()
            await PushNotifications.shared.uploadIfPossible()
            await ShareSync.renewIfNeeded()
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

#if DEBUG
/// Screenshots only: the tour opened on a chosen card, with no server.
struct TourViewPreview: View {
    private var start: Int {
        let name = PreviewMode.screen ?? ""
        return name == "tour-parent" ? 4 : Int(name.dropFirst(5)) ?? 0
    }
    var body: some View { TourView(hasParent: false, startPage: start) { _ in } }
}
#endif
