import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var inbox: InboxModel
    @EnvironmentObject private var model: HomeModel

    var body: some View {
        Scaffold(maxWidth: 560) {
            hero
            if let error = model.error, model.data == nil {
                EmptyState(pose: .peek, title: "משהו לא נטען", message: error, actionTitle: "נסו שוב") {
                    Task { await model.load() }
                }
            }
            if let data = model.data {
                if let live = data.lessons.first(where: { $0.phase == .live }) { liveCard(live) }
                challengeCard(data.dailyChallenge)
                lugichatCard(data.lugichat)
                lessonsSection(data.lessons.filter { $0.phase != .ended })
                groupsSection(data.groups)
                libraryTile
            } else if model.error == nil {
                ProgressView().controlSize(.large).padding(.top, 30)
            }
        }
        .refreshable { await model.load() }
    }

    // MARK: Hero

    private var firstName: String {
        model.data?.student.name.split(separator: " ").first.map(String.init) ?? ""
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Theme.brand700, Theme.brand500, Theme.violet500],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(HebrewDate.longDay(Date()))
                        .font(.heebo(13, 600)).foregroundStyle(.white.opacity(0.78))
                    Text(firstName.isEmpty ? "שלום 👋" : "שלום, \(firstName) 👋")
                        .font(.heebo(28, 800)).foregroundStyle(.white)
                    HStack(spacing: 8) {
                        if let streak = model.data?.dailyChallenge.streak, streak > 0 {
                            chip("🔥 \(streak) ימים") {}
                        }
                        chip(inbox.unread > 0 ? "🔔 \(inbox.unread) חדשות" : "🔔 התראות") { router.showAlerts = true }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                Lugi(pose: .wave, height: 128)
            }
            .padding(.horizontal, 22).padding(.top, 20)
        }
        .frame(minHeight: 168)
        .shadow(color: Theme.brand600.opacity(0.28), radius: 18, y: 10)
    }

    private func chip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.heebo(13, 700)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Cards

    private func liveCard(_ lesson: StudentHome.Lesson) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Theme.emerald500).frame(width: 10, height: 10)
                Text("השיעור מתקיים עכשיו").font(.heebo(14, 800)).foregroundStyle(Theme.emerald700)
            }
            Text(lesson.title).font(.heebo(22, 800)).foregroundStyle(Theme.ink)
            Text([lesson.teacher.map { "עם \($0)" }, HebrewDate.timeRange(lesson.scheduledAt, minutes: lesson.durationMin)]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.heebo(15, 500)).foregroundStyle(Theme.slate600)
            Button { router.open(path: "/meeting/lesson/\(lesson.id)") } label: {
                Label("הצטרפות לשיעור", systemImage: "video.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20, fill: Theme.emerald50, border: Theme.emerald200)
    }

    private func challengeCard(_ daily: StudentHome.Daily) -> some View {
        Button { router.tab = .practice } label: {
            HStack(spacing: 14) {
                Text(daily.doneToday ? "🎉" : "🔥").font(.system(size: 28))
                    .frame(width: 56, height: 56)
                    .background(daily.doneToday ? Theme.emerald100 : Theme.amber100, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("האתגר היומי").font(.heebo(18, 800)).foregroundStyle(Theme.ink)
                    Text(daily.doneToday ? "סיימתם להיום. חוזרים מחר לשמור על הרצף." : "כמה שאלות קצרות. שומרים על הרצף.")
                        .font(.heebo(14, 500)).foregroundStyle(Theme.slate600).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.slate400)
            }
            .card(padding: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func lugichatCard(_ quota: Quota?) -> some View {
        Button { router.tab = .lugichat } label: {
            HStack(spacing: 14) {
                Image(systemName: "camera.viewfinder").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.brand700)
                    .frame(width: 56, height: 56)
                    .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("תקועים בשאלה?").font(.heebo(18, 800)).foregroundStyle(Theme.ink)
                    Text(quotaLine(quota)).font(.heebo(14, 500)).foregroundStyle(Theme.slate600).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.slate400)
            }
            .card(padding: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quotaLine(_ q: Quota?) -> String {
        guard let left = q?.freeLeft else { return "צלמו את השאלה ולוגי ידריך אתכם צעד אחר צעד." }
        let pack = q?.packLeft ?? 0
        if left + pack > 0 { return "צלמו את השאלה ולוגי ידריך אתכם. נשארו \(left + pack) תשובות להיום." }
        return "התשובות של היום נגמרו. מחר מתחדשות."
    }

    // MARK: Lessons, groups, library

    @ViewBuilder
    private func lessonsSection(_ lessons: [StudentHome.Lesson]) -> some View {
        VStack(spacing: 10) {
            SectionTitle(text: "השיעורים הקרובים", count: lessons.count)
            if lessons.isEmpty {
                EmptyState(pose: .sit, title: "אין שיעורים קרובים", message: "כשתשובצו לקבוצה, השיעורים יופיעו כאן.")
            } else {
                ForEach(lessons) { l in
                    HStack(spacing: 14) {
                        VStack(spacing: 0) {
                            Text(HebrewDate.dayNumber(l.scheduledAt)).font(.heebo(22, 800)).foregroundStyle(Theme.brand700)
                            Text(HebrewDate.weekday(l.scheduledAt)).font(.heebo(12, 700)).foregroundStyle(Theme.brand700.opacity(0.8))
                        }
                        .frame(width: 58, height: 58)
                        .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(l.title).font(.heebo(17, 800)).foregroundStyle(Theme.ink)
                            Text([HebrewDate.dayLabel(l.scheduledAt), HebrewDate.timeRange(l.scheduledAt, minutes: l.durationMin)].joined(separator: " · "))
                                .font(.heebo(13, 500)).foregroundStyle(Theme.slate500)
                        }
                        Spacer(minLength: 6)
                        if l.phase == .live {
                            Button("הצטרפות") { router.open(path: "/meeting/lesson/\(l.id)") }.buttonStyle(SoftButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14)
                }
            }
        }
    }

    @ViewBuilder
    private func groupsSection(_ groups: [StudentHome.Group]) -> some View {
        if !groups.isEmpty {
            VStack(spacing: 10) {
                SectionTitle(text: "הקבוצות שלי", count: groups.count)
                ForEach(groups) { g in
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill").foregroundStyle(Theme.brand600)
                            .frame(width: 44, height: 44)
                            .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(g.title).font(.heebo(16, 800)).foregroundStyle(Theme.ink)
                            Text([g.teacher.map { "עם \($0)" }, "\(g.members) תלמידים", g.weekly > 1 ? "\(g.weekly) שיעורים בשבוע" : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.heebo(13, 500)).foregroundStyle(Theme.slate500)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14)
                }
            }
        }
    }

    private var libraryTile: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.slate400)
                .frame(width: 50, height: 50)
                .background(Theme.slate100, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("ספריית הסרטונים").font(.heebo(17, 800)).foregroundStyle(Theme.slate600)
                Text("בקרוב").font(.heebo(13, 700)).foregroundStyle(Theme.amber800)
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(Theme.amber100, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, fill: Theme.slate50)
        .accessibilityElement(children: .combine)
    }
}
