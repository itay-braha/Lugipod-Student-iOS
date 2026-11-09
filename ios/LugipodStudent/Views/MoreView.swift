import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var inbox: InboxModel
    @EnvironmentObject private var home: HomeModel
    @State private var confirmSignOut = false
    @State private var showAvailability = false
    @State private var showHistory = false
    @State private var showProfile = false
    @State private var showShareHowTo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        row("bell.fill", "התראות", color: Theme.brand600, badge: inbox.unread) { router.showAlerts = true }
                        divider
                        row("calendar.badge.clock", "השעות שלי", detail: "מתי נוח לכם ללמוד", color: Theme.emerald600) { showAvailability = true }
                        divider
                        row("clock.arrow.circlepath", "השיעורים שלי", detail: "כל השיעורים והסיכומים, גם מקבוצות קודמות", color: Theme.brand500) { showHistory = true }
                        divider
                        row("person.3.fill", "הקבוצות והשיעורים", detail: "כל הפרטים באתר", color: Theme.orange500) { router.open(path: "/dashboard") }
                        divider
                        row("sparkles.rectangle.stack.fill", "סיור היכרות", detail: "לוגיפוקס מראה איך הכל עובד", color: Theme.violet500) { router.showTour = true }
                        divider
                        row("square.and.arrow.up.fill", "שליחת תמונה ללוגיפוד", detail: "מוואטסאפ, מהגלריה ומכל אפליקציה", color: Theme.orange500) { showShareHowTo = true }
                        divider
                        row("lifepreserver.fill", "תמיכה", color: Color(hex: 0x0EA5E9)) { router.open(path: "/support") }
                        divider
                        row("hand.raised.fill", "פרטיות", color: Theme.violet500) { router.open(path: "/privacy") }
                    }
                    .card(padding: 4)

                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.slate500)
                        Text("ספריית הסרטונים").font(.heebo(16, 800)).foregroundStyle(Theme.slate700)
                        Text("בקרוב").font(.heebo(12, 800)).foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 3).background(Theme.orange500, in: Capsule())
                        Spacer()
                    }
                    .padding(16).background(Theme.slate100, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button("התנתקות") { confirmSignOut = true }.buttonStyle(SecondaryButtonStyle()).padding(.top, 6)

                    Text("לוגיפוד · גרסה \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.heebo(12, 600)).foregroundStyle(Theme.slate500)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(ScreenBackground())
        #if DEBUG
        .onAppear {
            if PreviewMode.screen == "availability" { showAvailability = true }
            if PreviewMode.screen == "history" { showHistory = true }
            if PreviewMode.screen == "profile" { showProfile = true }
        }
        #endif
        .confirmationDialog("להתנתק מהחשבון?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("התנתקות", role: .destructive) { Task { await auth.signOut() } }
            Button("ביטול", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showAvailability) {
            AvailabilityView().environment(\.layoutDirection, .rightToLeft)
        }
        .fullScreenCover(isPresented: $showHistory) {
            HistoryView().environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet { Task { await home.load() } }.presentationDetents([.large]).presentationDragIndicator(.visible).environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showShareHowTo) { ShareHowToSheet() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { showProfile = true } label: {
                AvatarView(name: home.data?.student.name ?? "", avatar: home.data?.badge?.avatar, frame: home.data?.badge?.frame, size: 60)
                    .overlay(RoundedRectangle(cornerRadius: 60 * 0.32, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 2.5))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 5) {
                Text("עוד").font(.heebo(13, 800)).foregroundStyle(Theme.gold300)
                Text(home.data?.student.name ?? "").font(.heebo(24, 900)).foregroundStyle(.white).lineLimit(1)
                if let title = home.data?.badge?.title { TitleChip(title: title) }
            }
            Spacer()
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20).padding(.top, ScreenInsets.top + 14).padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Theme.hero
                RadialGradient(colors: [Theme.orange500.opacity(0.5), .clear], center: .bottomLeading, startRadius: 0, endRadius: 280)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous))
            .shadow(color: Theme.brand800.opacity(0.3), radius: 14, y: 7)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var divider: some View { Divider().padding(.horizontal, 14) }

    private func row(_ icon: String, _ title: String, detail: String? = nil, color: Color, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: color.opacity(0.35), radius: 5, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.heebo(17, 800)).foregroundStyle(Theme.ink)
                    if let detail { Text(detail).font(.heebo(12, 600)).foregroundStyle(Theme.slate500) }
                }
                Spacer(minLength: 6)
                if badge > 0 {
                    Text("\(badge)").font(.heebo(12, 900)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Theme.orange500, in: Capsule())
                }
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.slate400)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
