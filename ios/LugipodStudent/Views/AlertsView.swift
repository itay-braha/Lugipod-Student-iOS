import SwiftUI

/// The bell, natively. Tapping an alert marks it read and opens the screen it is about.
struct AlertsView: View {
    @EnvironmentObject private var inbox: InboxModel
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Scaffold(maxWidth: 760) {
            ScreenHeader(title: "התראות",
                         subtitle: inbox.unread > 0 ? "\(inbox.unread) חדשות" : "הכל נקרא") {
                if inbox.unread > 0 {
                    Button("סימון הכל כנקרא") { Task { await inbox.markAllRead() } }
                        .buttonStyle(SoftButtonStyle())
                }
            }

            if inbox.alerts.isEmpty, inbox.loaded {
                EmptyState(pose: .sit, title: "אין התראות", message: "כשיהיה משהו חדש, תראו אותו כאן ותקבלו הודעה.")
            } else if inbox.alerts.isEmpty {
                if let error = inbox.error {
                    EmptyState(pose: .peek, title: "משהו לא נטען", message: error, actionTitle: "נסו שוב") {
                        Task { await inbox.load() }
                    }
                } else {
                    ProgressView().controlSize(.large).padding(.top, 40)
                }
            } else {
                ForEach(inbox.alerts) { alert in
                    Button {
                        Task { await inbox.markRead([alert.id]) }
                        router.open(path: alert.path)
                    } label: { AlertRow(alert: alert) }
                        .buttonStyle(.plain)
                }
            }
        }
        .refreshable { await inbox.load() }
    }
}

struct AlertRow: View {
    let alert: AlertItem

    private var tint: (fg: Color, bg: Color) {
        switch alert.type {
        case let t where t.hasPrefix("sos"): return (Theme.rose600, Theme.rose50)
        case let t where t.hasPrefix("lesson"): return (Theme.brand700, Theme.brand50)
        case let t where t.contains("pay"): return (Theme.emerald700, Theme.emerald50)
        default: return (Theme.slate600, Theme.slate100)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(alert.emoji ?? "🔔").font(.system(size: 24))
                .frame(width: 50, height: 50)
                .background(tint.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title).font(.heebo(17, alert.isUnread ? 800 : 600)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if let body = alert.body, !body.isEmpty {
                    Text(body).font(.heebo(14, 500)).foregroundStyle(Theme.slate600)
                        .multilineTextAlignment(.leading).lineLimit(3)
                }
                Text(HebrewDate.relative(alert.createdAt)).font(.heebo(12, 600)).foregroundStyle(Theme.slate400)
            }
            Spacer(minLength: 0)
            if alert.isUnread {
                Circle().fill(Theme.brand600).frame(width: 10, height: 10).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, fill: alert.isUnread ? Theme.brand50.opacity(0.6) : .white,
              border: alert.isUnread ? Theme.brand200 : Theme.slate200)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
