import SwiftUI

/// What a student can do with one lesson (server migration 0258, the same routes as the website): say they can't make it (up to 3 hours
/// before, once a month, not charged), move only this lesson (to a time the whole group marked; everyone must agree; the teacher or a
/// one-time replacement teaches it), or ask to change the weekly time for good (the admins decide).
struct LessonOptions: Decodable, Equatable {
    struct Candidate: Decodable, Equatable, Hashable { let at: Date; let teacherOk: Bool }
    struct OpenRequest: Decodable, Equatable { let id: String; let kind: String; let status: String; let proposedAt: Date?; let proposedSlot: Int?; let mine: Bool }
    let lessonId: String
    let scheduledAt: Date
    let groupSize: Int
    let excuse: String           // ok | excused | used | too_late | closed
    let canMove: Bool
    let onceCandidates: [Candidate]
    let permanentCandidates: [Int]
    let openRequest: OpenRequest?
}

@MainActor
final class LessonChangeModel: ObservableObject {
    enum Mode: Equatable { case menu, confirmExcuse, once, permanent }
    @Published private(set) var options: LessonOptions?
    @Published var mode: Mode = .menu
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var loadFailed = false
    let lessonId: String

    init(lessonId: String) { self.lessonId = lessonId }

    func load() async {
        loadFailed = false
        do {
            let raw = try await API.request("GET", "/api/student/lesson/\(lessonId)/options")
            options = try API.decoder.decode(LessonOptions.self, from: raw)
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch { loadFailed = true }
    }

    /// Posts and shows the server's sentence (it says what happens next); on success the options are reloaded and Home refreshed.
    func post(_ path: String, _ body: [String: Any], onDone: @escaping () -> Void) async {
        busy = true
        defer { busy = false }
        struct Reply: Decodable { let ok: Bool?; let message: String? }
        do {
            let raw = try await API.request("POST", path, json: body, timeout: 30)
            let r = try? API.decoder.decode(Reply.self, from: raw)
            message = r?.message ?? "נשלח ✓"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            mode = .menu
            await load()
            onDone()
        } catch APIError.server(_, let m) where !m.isEmpty {
            message = m
        } catch APIError.server(let status, _) where status == 409 {
            message = "לא הצלחנו. נסו שוב."
        } catch {
            message = "אין חיבור כרגע. נסו שוב."
        }
    }

    static func slotLabel(_ s: Int) -> String {
        let days = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"]
        let half = s % 48
        return "יום \(days[min(6, s / 48)]) \(String(format: "%02d", half / 2)):\(half % 2 == 1 ? "30" : "00")"
    }
}

struct LessonChangeSheet: View {
    @StateObject private var model: LessonChangeModel
    @Environment(\.dismiss) private var dismiss
    var onChanged: () -> Void
    @State private var pickOnce: Date?
    @State private var pickSlot: Int?          // -1 = any time that suits me
    @State private var note = ""

    init(lessonId: String, onChanged: @escaping () -> Void) {
        _model = StateObject(wrappedValue: LessonChangeModel(lessonId: lessonId))
        self.onChanged = onChanged
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let o = model.options {
                        Text("השיעור של \(HebrewDate.dayLabel(o.scheduledAt)) · \(HebrewDate.time(o.scheduledAt))")
                            .font(.heebo(14, 700)).foregroundStyle(Theme.slate600)
                        if let m = model.message {
                            Text(m).font(.heebo(14, 800)).foregroundStyle(Theme.brand700)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        if let r = o.openRequest { openRequestNote(r) }
                        switch model.mode {
                        case .menu: menu(o)
                        case .confirmExcuse: confirmExcuse(o)
                        case .once: once(o)
                        case .permanent: permanent(o)
                        }
                    } else if model.loadFailed {
                        ContentUnavailableView {
                            Label("לא הצלחנו לטעון", systemImage: "wifi.exclamationmark")
                        } actions: {
                            Button("נסו שוב") { Task { await model.load() } }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(40)
                    }
                }
                .padding(18)
            }
            .navigationTitle("שינוי מועד")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגירה") { dismiss() } } }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .task { await model.load() }
    }

    // MARK: - parts

    private func openRequestNote(_ r: LessonOptions.OpenRequest) -> some View {
        let status = ["voting": "מחכים לתשובה של שאר הקבוצה", "teacher": "מחכים לתשובת המורה", "cover": "מחפשים מורה מחליף/ה לזמן החדש", "admin": "הבקשה אצלנו, נחזור אליך"][r.status] ?? ""
        let what = r.kind == "once" && r.proposedAt != nil ? "בקשה להזיז ל\(HebrewDate.dayLabel(r.proposedAt!)) \(HebrewDate.time(r.proposedAt!))" : "בקשה לשינוי השעה הקבועה"
        return Label("\(what): \(status)", systemImage: "hourglass")
            .font(.heebo(13, 700)).foregroundStyle(Theme.amber800)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.amber50, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func menu(_ o: LessonOptions) -> some View {
        VStack(spacing: 12) {
            option(icon: "hand.raised.fill", title: "לא אוכל להגיע לשיעור הזה", tint: Theme.rose600,
                   note: excuseNote(o.excuse), enabled: o.excuse == "ok" && !model.busy) { model.mode = .confirmExcuse }
            option(icon: "calendar.badge.clock", title: "להזיז רק את השיעור הזה", tint: Theme.brand600,
                   note: (o.groupSize > 1 ? "לזמן שכל הקבוצה סימנה כנוח. כולם צריכים להסכים." : "לזמן שסימנת כנוח.") + " עד 3 שעות לפני השיעור.",
                   enabled: o.canMove && o.openRequest == nil && !model.busy) { model.mode = .once }
            option(icon: "arrow.triangle.2.circlepath", title: "לשנות את השעה הקבועה", tint: Theme.slate700,
                   note: "נבדוק ונחזור אליך: אולי כל הקבוצה עוברת, ואולי קבוצה אחרת בשעה שמתאימה לך.",
                   enabled: o.openRequest?.kind != "permanent" && !model.busy) { model.mode = .permanent }
        }
    }

    private func excuseNote(_ s: String) -> String {
        switch s {
        case "ok": return "אפשר פעם בחודש, עד 3 שעות לפני השיעור. לא תחויבו על השיעור."
        case "excused": return "הודעת שלא תגיע/י לשיעור הזה. לא תחויב/י עליו."
        case "used": return "כבר השתמשת החודש באפשרות הזו (פעם בחודש)."
        case "too_late": return "אפשר להודיע עד 3 שעות לפני השיעור."
        default: return "השיעור כבר לא פתוח לשינויים."
        }
    }

    private func option(icon: String, title: String, tint: Color, note: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.heebo(16, 900)).foregroundStyle(tint)
                Text(note).font(.heebo(12, 600)).foregroundStyle(Theme.slate500).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func confirmExcuse(_ o: LessonOptions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("נעדכן את המורה. " + (o.groupSize > 1 ? "השיעור יתקיים כרגיל עם שאר הקבוצה, " : "השיעור יבוטל, ") + "ולא תחויבו עליו. אפשר פעם אחת בחודש.")
                .font(.heebo(15, 600)).foregroundStyle(Theme.ink)
            Button { Task { await model.post("/api/student/lesson/\(o.lessonId)/excuse", [:], onDone: onChanged) } } label: {
                HStack { if model.busy { ProgressView().tint(.white) }; Text("כן, לא אוכל להגיע") }
            }
            .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.rose600))
            .disabled(model.busy)
            Button("חזרה") { model.mode = .menu }.font(.heebo(14, 700)).foregroundStyle(Theme.slate500)
        }
    }

    private func once(_ o: LessonOptions) -> some View {
        let byDay = Dictionary(grouping: o.onceCandidates) { Calendar.current.startOfDay(for: $0.at) }
        return VStack(alignment: .leading, spacing: 12) {
            if byDay.isEmpty {
                Text("אין כרגע זמן אחר שכל הקבוצה סימנה כנוח בשבוע הקרוב. עדכנו את \"השעות שלי\", או הודיעו שלא תוכלו להגיע.")
                    .font(.heebo(14, 600)).foregroundStyle(Theme.slate600)
            } else {
                ForEach(byDay.keys.sorted(), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(HebrewDate.dayLabel(day)).font(.heebo(13, 800)).foregroundStyle(Theme.slate500)
                        FlowChips(items: byDay[day]!.map(\.at).sorted(), selected: pickOnce, label: { HebrewDate.time($0) }) { pickOnce = $0 }
                    }
                }
            }
            Button {
                guard let at = pickOnce else { return }
                let iso = ISO8601DateFormatter().string(from: at)
                Task { await model.post("/api/student/lesson/\(o.lessonId)/reschedule", ["kind": "once", "at": iso], onDone: onChanged) }
            } label: { HStack { if model.busy { ProgressView().tint(.white) }; Text("שליחת הבקשה") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.busy || pickOnce == nil)
            Button("חזרה") { model.mode = .menu }.font(.heebo(14, 700)).foregroundStyle(Theme.slate500)
        }
    }

    private func permanent(_ o: LessonOptions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("זמנים שכל הקבוצה סימנה כנוחים (או \"כל זמן שמתאים לי\"):").font(.heebo(13, 700)).foregroundStyle(Theme.slate500)
            FlowChips(items: Array(o.permanentCandidates.prefix(18)) + [-1], selected: pickSlot,
                      label: { $0 < 0 ? "כל זמן שמתאים לי" : LessonChangeModel.slotLabel($0) }) { pickSlot = $0 }
            TextField("משהו שכדאי שנדע? (רשות)", text: $note, axis: .vertical)
                .lineLimit(2...4).font(.heebo(15, 500))
                .padding(12).background(Theme.slate50, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                guard let s = pickSlot else { return }
                var body: [String: Any] = ["kind": "permanent", "note": note]
                if s >= 0 { body["slot"] = s }
                Task { await model.post("/api/student/lesson/\(o.lessonId)/reschedule", body, onDone: onChanged) }
            } label: { HStack { if model.busy { ProgressView().tint(.white) }; Text("שליחה") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.busy || pickSlot == nil)
            Button("חזרה") { model.mode = .menu }.font(.heebo(14, 700)).foregroundStyle(Theme.slate500)
        }
    }
}

/// Wrapping chips, one selectable.
struct FlowChips<T: Hashable>: View {
    let items: [T]
    let selected: T?
    let label: (T) -> String
    let onPick: (T) -> Void

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let on = item == selected
                Button { onPick(item) } label: {
                    Text(label(item)).font(.heebo(14, 800)).foregroundStyle(on ? .white : Theme.slate700)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? Theme.brand600 : Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Theme.brand600 : Theme.slate200, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A simple wrapping row layout (chips flow onto the next line).
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

/// A classmate asked to move one lesson: "does the new time work for you?" (everyone in the group must agree, server 0258).
struct RescheduleVoteCard: View {
    let vote: StudentHome.RescheduleVote
    var onAnswered: () -> Void
    @State private var busy = false
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(vote.by.isEmpty ? "חבר/ה בקבוצה" : vote.by) מבקש/ת להזיז שיעור", systemImage: "calendar.badge.clock")
                .font(.heebo(16, 900)).foregroundStyle(Theme.brand700)
            Text((vote.from.map { "מ\(HebrewDate.dayLabel($0)) \(HebrewDate.time($0)) " } ?? "") + "ל\(HebrewDate.dayLabel(vote.to)) \(HebrewDate.time(vote.to)) (רק הפעם). מתאים לך?")
                .font(.heebo(14, 600)).foregroundStyle(Theme.ink)
            if let done {
                Text(done).font(.heebo(14, 800)).foregroundStyle(Theme.emerald700)
            } else {
                HStack(spacing: 10) {
                    Button { Task { await answer(true) } } label: { HStack { if busy { ProgressView().tint(.white) }; Text("מתאים לי") } }
                        .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.brand600))
                    Button("לא מתאים") { Task { await answer(false) } }
                        .font(.heebo(14, 800)).foregroundStyle(Theme.slate600)
                }
                .disabled(busy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, fill: Theme.brand50, border: Theme.brand200)
    }

    private func answer(_ yes: Bool) async {
        busy = true
        defer { busy = false }
        struct Reply: Decodable { let message: String? }
        do {
            let raw = try await API.request("POST", "/api/student/reschedule/\(vote.id)/vote", json: ["yes": yes])
            done = (try? API.decoder.decode(Reply.self, from: raw))?.message ?? "תודה!"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            onAnswered()
        } catch APIError.server(_, let m) where !m.isEmpty {
            done = m
        } catch {
            done = "אין חיבור כרגע. נסו שוב."
        }
    }
}
