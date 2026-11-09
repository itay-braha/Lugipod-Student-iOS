import SwiftUI

/// Per-subject colours and icon, so a glance at a card says which subject it is. Bold on purpose: the card's header is the subject's own colour.
struct SubjectTint {
    let fg: Color
    let bg: Color
    let accent: Color
    let icon: String
    let gradient: LinearGradient

    private static func make(_ fg: Color, _ bg: Color, _ accent: Color, _ icon: String, _ a: UInt32, _ b: UInt32) -> SubjectTint {
        SubjectTint(fg: fg, bg: bg, accent: accent, icon: icon,
                    gradient: LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    static func of(_ subject: String) -> SubjectTint {
        if subject.contains("פיזיקה") { return make(Theme.sky800, Theme.sky50, Color(hex: 0x0EA5E9), "atom", 0x0369A1, 0x0EA5E9) }
        if subject.contains("מחשב") { return make(Theme.violet700, Theme.violet50, Theme.violet500, "chevron.left.forwardslash.chevron.right", 0x6D28D9, 0xC026D3) }
        if subject.contains("כימיה") { return make(Theme.emerald700, Theme.emerald50, Theme.emerald500, "flask.fill", 0x047857, 0x14B8A6) }
        if subject.contains("מתמטיקה") { return make(Theme.brand700, Theme.brand50, Theme.brand500, "function", 0x3730A3, 0x6366F1) }
        return make(Theme.brand700, Theme.brand50, Theme.brand500, "book.fill", 0x3730A3, 0x6366F1)
    }
}

/// One group: what it is, who teaches and who is in it, when the next lesson is (with a join button when it is on), the homework state,
/// and the two things a student does from here: ask the teacher something before the lesson, and look back at past lessons.
struct GroupCard: View {
    let group: StudentHome.Group
    var onAsk: () -> Void
    var onJoin: (String) -> Void
    var onHomework: () -> Void
    /// "שינוי מועד": can't make it / move this lesson / change the weekly time (server 0258). Nil = not offered here.
    var onChange: ((StudentHome.Lesson) -> Void)? = nil

    var body: some View {
        // Re-evaluated every 30 s, so "join" appears on time without a refresh.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let tint = SubjectTint.of(group.subject)
        let next = group.nextLesson(now: now)
        let live = next?.phase(now: now) == .live
        return VStack(spacing: 0) {
            // The subject's colour, as a solid header with white text.
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: tint.icon).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title).font(.heebo(18, 800)).foregroundStyle(.white).lineLimit(2)
                    if let teacher = group.teacher {
                        Label("עם \(teacher)", systemImage: "person.fill").font(.heebo(13, 700)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer(minLength: 0)
                if live { Text("● חי").font(.heebo(12, 900)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4).background(Theme.emerald500, in: Capsule()) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.gradient)

            VStack(alignment: .leading, spacing: 14) {
                if !group.mates.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(tint.accent)
                        Text(group.mates.joined(separator: ", ")).font(.heebo(14, 700)).foregroundStyle(Theme.slate700).lineLimit(1)
                    }
                }
                nextLessonRow(next: next, live: live, now: now)
                homeworkRow
                actions(tint: tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(live ? Theme.emerald500 : tint.accent.opacity(0.35), lineWidth: live ? 3 : 1.5))
        .shadow(color: tint.accent.opacity(0.22), radius: 12, y: 6)
    }

    @ViewBuilder
    private func nextLessonRow(next: StudentHome.Lesson?, live: Bool, now: Date) -> some View {
        if let next {
            HStack(spacing: 12) {
                // The date, in the warm colours: orange normally, green when the lesson is on.
                VStack(spacing: 0) {
                    Text(HebrewDate.dayNumber(next.scheduledAt)).font(.heebo(23, 900))
                    Text(HebrewDate.weekday(next.scheduledAt)).font(.heebo(11, 800))
                }
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(live ? AnyShapeStyle(Theme.emerald600) : AnyShapeStyle(Theme.cta), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: (live ? Theme.emerald600 : Theme.orange600).opacity(0.35), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(live ? "השיעור מתקיים עכשיו" : (next.extra ? "שיעור נוסף" : "השיעור הבא"))
                        .font(.heebo(12, 800)).foregroundStyle(live ? Theme.emerald700 : Theme.orange600)
                    Text(HebrewDate.timeRange(next.scheduledAt, minutes: next.durationMin)).font(.heebo(18, 900)).foregroundStyle(Theme.ink)
                    Text(live ? HebrewDate.dayLabel(next.scheduledAt) : "\(HebrewDate.dayLabel(next.scheduledAt)) · \(HebrewDate.relative(next.scheduledAt, now: now))")
                        .font(.heebo(12, 600)).foregroundStyle(Theme.slate500)
                    if next.excused == true {
                        Label("הודעת שלא תגיע/י · בלי חיוב", systemImage: "hand.raised.fill").font(.heebo(12, 800)).foregroundStyle(Theme.rose600)
                    } else if let from = next.movedFrom {
                        Label("הוזז מ\(HebrewDate.weekday(from)) \(HebrewDate.time(from))", systemImage: "arrow.uturn.left").font(.heebo(12, 800)).foregroundStyle(Theme.brand600)
                    }
                    if !live, let onChange {
                        Button { onChange(next) } label: {
                            Text("שינוי מועד / לא אוכל להגיע").font(.heebo(12, 800)).foregroundStyle(Theme.brand600).underline()
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 6)
                if live {
                    Button { onJoin(next.id) } label: { Label("הצטרפות", systemImage: "video.fill") }
                        .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.emerald600))
                }
            }
        } else {
            Label("אין שיעור מתוכנן כרגע", systemImage: "calendar").font(.heebo(14, 600)).foregroundStyle(Theme.slate500)
        }
    }

    @ViewBuilder private var homeworkRow: some View {
        let open = group.homework.first { !$0.isDone }
        Button(action: onHomework) {
            HStack(spacing: 10) {
                if let open {
                    Image(systemName: "pencil.and.list.clipboard").foregroundStyle(Theme.orange600)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("שיעורי בית ממתינים").font(.heebo(12, 800)).foregroundStyle(Theme.orange700)
                        Text("\(open.title) · \(open.correct)/\(open.total)").font(.heebo(14, 800)).foregroundStyle(Theme.ink).lineLimit(1)
                    }
                } else if !group.homework.isEmpty {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.emerald600)
                    Text("כל שיעורי הבית הושלמו").font(.heebo(14, 800)).foregroundStyle(Theme.emerald700)
                } else if let text = group.last?.homeworkText, !text.isEmpty {
                    Image(systemName: "pencil.and.list.clipboard").foregroundStyle(Theme.brand600)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("שיעורי בית מהשיעור האחרון").font(.heebo(12, 800)).foregroundStyle(Theme.brand700)
                        Text(text).font(.heebo(14, 700)).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                    }
                } else {
                    Image(systemName: "checkmark.circle").foregroundStyle(Theme.slate400)
                    Text("אין שיעורי בית פתוחים").font(.heebo(14, 600)).foregroundStyle(Theme.slate500)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(open != nil ? Theme.orange100 : (group.homework.isEmpty ? Theme.slate50 : Theme.emerald50), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func actions(tint: SubjectTint) -> some View {
        HStack(spacing: 10) {
            Button(action: onAsk) {
                Label(group.myQuestions > 0 ? "שאלה למורה (\(group.myQuestions))" : "שאלה למורה", systemImage: "square.and.pencil")
            }
            .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.orange500))
            HStack(spacing: 4) {
                Text(group.pastCount > 0 ? "לשיעורים קודמים (\(group.pastCount))" : "פרטי הקבוצה")
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            }
            .font(.heebo(14, 800)).foregroundStyle(tint.fg)
            .padding(.horizontal, 6)
            Spacer(minLength: 0)
        }
    }
}
