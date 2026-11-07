import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var inbox: InboxModel
    @EnvironmentObject private var home: HomeModel
    @State private var confirmSignOut = false

    var body: some View {
        Scaffold(maxWidth: 560) {
            ScreenHeader(title: "עוד", subtitle: home.data?.student.name)

            VStack(spacing: 0) {
                row("bell.fill", "התראות", badge: inbox.unread) { router.showAlerts = true }
                divider
                row("calendar.badge.clock", "הזמינות שלי", detail: "באילו שעות נוח לכם ללמוד") { router.open(path: "/dashboard#availability") }
                divider
                row("person.3.fill", "הקבוצות והשיעורים", detail: "כל הפרטים באתר") { router.open(path: "/dashboard") }
                divider
                row("lifepreserver.fill", "תמיכה") { router.open(path: "/support") }
                divider
                row("hand.raised.fill", "פרטיות") { router.open(path: "/privacy") }
            }
            .card(padding: 4)

            HStack(spacing: 14) {
                Image(systemName: "lock.fill").foregroundStyle(Theme.slate400)
                Text("ספריית הסרטונים").font(.heebo(16, 700)).foregroundStyle(Theme.slate600)
                Text("בקרוב").font(.heebo(12, 700)).foregroundStyle(Theme.amber800)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Theme.amber100, in: Capsule())
                Spacer()
            }
            .card(padding: 16, fill: Theme.slate50)

            Button("התנתקות") { confirmSignOut = true }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 8)

            Text("לוגיפוד · גרסה \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.heebo(12, 500)).foregroundStyle(Theme.slate400).padding(.top, 4)
        }
        .confirmationDialog("להתנתק מהחשבון?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("התנתקות", role: .destructive) { Task { await auth.signOut() } }
            Button("ביטול", role: .cancel) {}
        }
    }

    private var divider: some View { Divider().padding(.horizontal, 14) }

    private func row(_ icon: String, _ title: String, detail: String? = nil, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.brand600)
                    .frame(width: 38, height: 38)
                    .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.heebo(16, 700)).foregroundStyle(Theme.ink)
                    if let detail { Text(detail).font(.heebo(12, 500)).foregroundStyle(Theme.slate500) }
                }
                Spacer(minLength: 6)
                if badge > 0 {
                    Text("\(badge)").font(.heebo(12, 800)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Theme.rose500, in: Capsule())
                }
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.slate300)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
