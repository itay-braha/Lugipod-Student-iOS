import SwiftUI

/// Per-subject colours and icon, so a glance at a card says which subject it is.
struct SubjectTint {
    let fg: Color
    let bg: Color
    let accent: Color
    let icon: String

    static func of(_ subject: String) -> SubjectTint {
        if subject.contains("פיזיקה") { return SubjectTint(fg: Theme.sky800, bg: Theme.sky50, accent: Color(hex: 0x0EA5E9), icon: "atom") }
        if subject.contains("מחשב") { return SubjectTint(fg: Theme.violet700, bg: Theme.violet50, accent: Theme.violet500, icon: "chevron.left.forwardslash.chevron.right") }
        if subject.contains("כימיה") { return SubjectTint(fg: Theme.emerald700, bg: Theme.emerald50, accent: Theme.emerald500, icon: "flask.fill") }
        if subject.contains("מתמטיקה") { return SubjectTint(fg: Theme.brand700, bg: Theme.brand50, accent: Theme.brand500, icon: "function") }
        return SubjectTint(fg: Theme.brand700, bg: Theme.brand50, accent: Theme.brand500, icon: "book.fill")
    }
}

/// One group: what it is, who teaches and who is in it, when the next lesson is (with a join button when it is on), the homework state,
/// and the two things a student does from here: ask the teacher something before the lesson, and look back at past lessons.
struct GroupCard: View {
    let group: StudentHome.Group
    var onAsk: () -> Void
    var onJoin: (String) -> Void
    var onHomework: () -> Void

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
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: tint.icon).font(.system(size: 20, weight: .bold)).foregroundStyle(tint.fg)
                    .frame(width: 48, height: 48)
                    .background(tint.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title).font(.heebo(18, 800)).foregroundStyle(Theme.ink).lineLimit(2)
                    if let teacher = group.teacher {
                        Label("עם \(teacher)", systemImage: "person.fill").font(.heebo(13, 600)).foregroundStyle(Theme.slate600)
                            .labelStyle(.titleAndIcon)
                    }
                }
                Spacer(minLength: 0)
            }

            if !group.mates.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(tint.accent)
                    Text(group.mates.joined(separator: ", ")).font(.heebo(13, 600)).foregroundStyle(Theme.slate600).lineLimit(1)
                }
            }

            nextLessonRow(next: next, live: live, now: now, tint: tint)
            homeworkRow
            actions(tint: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            // White card with the subject colour as a bar along the top edge, clipped to the card's own rounded corners.
            ZStack(alignment: .top) {
                Color.white
                tint.accent.frame(height: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(live ? Theme.emerald500 : Theme.slate200, lineWidth: live ? 2 : 1))
        .shadow(color: Theme.shadowSoft1, radius: 1, y: 1)
        .shadow(color: Theme.shadowSoft2, radius: 8, y: 4)
    }

    @ViewBuilder
    private func nextLessonRow(next: StudentHome.Lesson?, live: Bool, now: Date, tint: SubjectTint) -> some View {
        if let next {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(HebrewDate.dayNumber(next.scheduledAt)).font(.heebo(20, 800))
                    Text(HebrewDate.weekday(next.scheduledAt)).font(.heebo(11, 700))
                }
                .foregroundStyle(live ? Theme.emerald700 : Theme.amber800)
                .frame(width: 54, height: 54)
                .background(live ? Theme.emerald100 : Theme.amber100, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(live ? "השיעור מתקיים עכשיו" : (next.extra ? "שיעור נוסף" : "השיעור הבא"))
                        .font(.heebo(12, 700)).foregroundStyle(live ? Theme.emerald700 : Theme.slate500)
                    Text(HebrewDate.timeRange(next.scheduledAt, minutes: next.durationMin)).font(.heebo(17, 800)).foregroundStyle(Theme.ink)
                    Text(live ? HebrewDate.dayLabel(next.scheduledAt) : "\(HebrewDate.dayLabel(next.scheduledAt)) · \(HebrewDate.relative(next.scheduledAt, now: now))")
                        .font(.heebo(12, 500)).foregroundStyle(Theme.slate500)
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
                    Image(systemName: "pencil.and.list.clipboard").foregroundStyle(Theme.amber800)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("שיעורי בית ממתינים").font(.heebo(12, 700)).foregroundStyle(Theme.amber800)
                        Text("\(open.title) · \(open.correct)/\(open.total)").font(.heebo(14, 700)).foregroundStyle(Theme.ink).lineLimit(1)
                    }
                } else if !group.homework.isEmpty {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.emerald600)
                    Text("כל שיעורי הבית הושלמו").font(.heebo(14, 700)).foregroundStyle(Theme.emerald700)
                } else if let text = group.last?.homeworkText, !text.isEmpty {
                    Image(systemName: "pencil.and.list.clipboard").foregroundStyle(Theme.brand600)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("שיעורי בית מהשיעור האחרון").font(.heebo(12, 700)).foregroundStyle(Theme.brand700)
                        Text(text).font(.heebo(14, 600)).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                    }
                } else {
                    Image(systemName: "checkmark.circle").foregroundStyle(Theme.slate400)
                    Text("אין שיעורי בית פתוחים").font(.heebo(14, 600)).foregroundStyle(Theme.slate500)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(open != nil ? Theme.amber50 : Theme.slate50, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func actions(tint: SubjectTint) -> some View {
        HStack(spacing: 10) {
            Button(action: onAsk) {
                Label(group.myQuestions > 0 ? "שאלה למורה (\(group.myQuestions))" : "שאלה למורה", systemImage: "square.and.pencil")
            }
            .buttonStyle(SoftButtonStyle(fg: tint.fg, bg: tint.bg))
            HStack(spacing: 4) {
                Text(group.pastCount > 0 ? "שיעורים קודמים (\(group.pastCount))" : "פרטי הקבוצה")
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            }
            .font(.heebo(14, 700)).foregroundStyle(Theme.slate600)
            .padding(.horizontal, 10)
            Spacer(minLength: 0)
        }
    }
}
