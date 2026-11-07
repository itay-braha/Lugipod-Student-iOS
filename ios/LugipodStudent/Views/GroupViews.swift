import SwiftUI

extension HebrewDate {
    /// "2026-11" → "נובמבר 2026".
    static func monthYear(_ period: String?) -> String {
        guard let period, period.count >= 7 else { return "" }
        let parts = period.split(separator: "-")
        guard parts.count >= 2, let m = Int(parts[1]), (1...12).contains(m) else { return "" }
        let months = ["ינואר", "פברואר", "מרץ", "אפריל", "מאי", "יוני", "יולי", "אוגוסט", "ספטמבר", "אוקטובר", "נובמבר", "דצמבר"]
        return "\(months[m - 1]) \(parts[0])"
    }
}

// MARK: - Model

@MainActor
final class GroupDetailModel: ObservableObject {
    @Published private(set) var detail: GroupDetail?
    @Published private(set) var failed = false

    func load(_ groupId: String) async {
        let key = "group-\(groupId)"
        if detail == nil, let raw = LocalCache.read(key), let d = try? API.decoder.decode(GroupDetail.self, from: raw) { detail = d }
        do {
            let raw = try await API.request("GET", "/api/native/student/group/\(groupId)")
            detail = try API.decoder.decode(GroupDetail.self, from: raw)
            LocalCache.write(key, raw)
            failed = false
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            if detail == nil { failed = true }
        }
    }
}

// MARK: - A group in full

struct GroupDetailView: View {
    let groupId: String
    @EnvironmentObject private var home: HomeModel
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = GroupDetailModel()
    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?

    private var group: StudentHome.Group? { home.data?.groups.first { $0.id == groupId } }

    var body: some View {
        Scaffold(maxWidth: 720) {
            if let group {
                let tint = SubjectTint.of(group.subject)
                GroupCard(group: group, onAsk: {}, onJoin: { router.open(path: "/meeting/lesson/\($0)") }, onHomework: { router.open(path: "/dashboard") })
                    .allowsHitTesting(true)
                upcoming(tint)
                homework(group)
                questions(group, tint: tint)
                past
            } else {
                ProgressView().padding(.top, 40)
            }
        }
        .navigationTitle(group?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await model.load(groupId) }
        .refreshable { await model.load(groupId); await home.load() }
    }

    @ViewBuilder private func upcoming(_ tint: SubjectTint) -> some View {
        if let up = model.detail?.upcoming, up.count > 1 {
            VStack(spacing: 8) {
                SectionTitle(text: "השיעורים הקרובים", count: up.count)
                ForEach(up) { l in
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").foregroundStyle(tint.accent)
                        Text(HebrewDate.dayLabel(l.scheduledAt)).font(.heebo(15, 700)).foregroundStyle(Theme.ink)
                        if l.extra { Pill(text: "נוסף", fg: Theme.amber800, bg: Theme.amber100) }
                        Spacer()
                        Text(HebrewDate.timeRange(l.scheduledAt, minutes: l.durationMin)).font(.heebo(13, 600)).foregroundStyle(Theme.slate500)
                    }
                    .card(padding: 12, radius: 16)
                }
            }
        }
    }

    @ViewBuilder private func homework(_ group: StudentHome.Group) -> some View {
        let sets = model.detail?.homework ?? []
        let lastText = group.last?.homeworkText ?? ""
        if !sets.isEmpty || !lastText.isEmpty {
            VStack(spacing: 8) {
                SectionTitle(text: "שיעורי בית", count: sets.count)
                if !lastText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("מהשיעור האחרון").font(.heebo(12, 700)).foregroundStyle(Theme.brand700)
                        Text(lastText).font(.heebo(15, 600)).foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14, radius: 16, fill: Theme.brand50.opacity(0.6), border: Theme.brand200)
                }
                ForEach(sets) { h in
                    Button { router.open(path: "/dashboard") } label: {
                        HStack(spacing: 12) {
                            Image(systemName: h.isDone ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 22)).foregroundStyle(h.isDone ? Theme.emerald500 : Theme.amber500)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.title).font(.heebo(15, 700)).foregroundStyle(Theme.ink)
                                Text(h.isDone ? "הושלם · \(h.correct) מתוך \(h.total) נכונות" : "\(h.correct) מתוך \(h.total) · ממתין לך")
                                    .font(.heebo(12, 600)).foregroundStyle(h.isDone ? Theme.emerald700 : Theme.amber800)
                            }
                            Spacer(minLength: 0)
                            if let due = h.dueDate, !h.isDone { Text(due).font(.heebo(12, 600)).foregroundStyle(Theme.slate500) }
                        }
                        .card(padding: 12, radius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func questions(_ group: StudentHome.Group, tint: SubjectTint) -> some View {
        VStack(spacing: 8) {
            SectionTitle(text: "שאלות למורה לפני השיעור", count: model.detail?.questions.count)
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("מה תרצו שנעבור? כתבו שאלה…", text: $draft, axis: .vertical)
                        .lineLimit(1...4).font(.heebo(16, 500))
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Theme.slate50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button {
                        Task { await send(group) }
                    } label: {
                        Image(systemName: sending ? "ellipsis" : "paperplane.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(canSend ? tint.accent : Theme.slate300, in: Circle())
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("שליחה למורה")
                }
                if let sendError { Text(sendError).font(.heebo(13, 600)).foregroundStyle(Theme.rose600) }
                ForEach(model.detail?.questions ?? []) { q in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "text.bubble.fill").foregroundStyle(tint.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.text).font(.heebo(14, 600)).foregroundStyle(Theme.ink)
                            Text(HebrewDate.relative(q.createdAt)).font(.heebo(11, 500)).foregroundStyle(Theme.slate400)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .card(padding: 14, radius: 18)
        }
    }

    private var canSend: Bool { !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send(_ group: StudentHome.Group) async {
        sending = true; sendError = nil
        defer { sending = false }
        do {
            _ = try await API.request("POST", "/api/native/student/lesson-question",
                                      json: ["groupId": group.id, "lessonId": group.nextLesson()?.id ?? NSNull(), "text": draft])
            draft = ""
            await model.load(groupId)
            await home.load()
        } catch {
            sendError = "לא הצלחנו לשלוח. נסו שוב."
        }
    }

    @ViewBuilder private var past: some View {
        VStack(spacing: 8) {
            SectionTitle(text: "שיעורים קודמים", count: model.detail?.past.count)
            if let past = model.detail?.past, !past.isEmpty {
                ForEach(past) { PastLessonRow(lesson: $0, groupTitle: nil) }
            } else if model.detail != nil {
                Text("עוד לא היו שיעורים בקבוצה הזו.").font(.heebo(14, 500)).foregroundStyle(Theme.slate500).padding(.top, 4)
            } else if model.failed {
                Text("לא הצלחנו לטעון את ההיסטוריה.").font(.heebo(14, 500)).foregroundStyle(Theme.rose600)
            }
        }
    }
}

struct PastLessonRow: View {
    let lesson: GroupDetail.Past
    let groupTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(HebrewDate.lessonText(lesson.scheduledAt)).font(.heebo(15, 800)).foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                if let attended = lesson.attended {
                    Pill(text: attended ? "הייתי" : "לא הגעתי", icon: attended ? "checkmark" : "xmark",
                         fg: attended ? Theme.emerald700 : Theme.rose600, bg: attended ? Theme.emerald50 : Theme.rose50)
                }
            }
            if let groupTitle { Text(groupTitle).font(.heebo(12, 700)).foregroundStyle(Theme.brand700) }
            if let topics = lesson.topics, !topics.isEmpty {
                Text(topics).font(.heebo(14, 500)).foregroundStyle(Theme.slate700)
            }
            if let hw = lesson.homeworkText, !hw.isEmpty {
                Label(hw, systemImage: "pencil.and.list.clipboard").font(.heebo(13, 600)).foregroundStyle(Theme.amber800)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 16)
    }
}

// MARK: - All groups, all past lessons

struct AllGroupsView: View {
    @Binding var path: [HomeRoute]
    @EnvironmentObject private var home: HomeModel
    @EnvironmentObject private var router: AppRouter
    @State private var askGroup: StudentHome.Group?

    var body: some View {
        Scaffold(maxWidth: 720) {
            ForEach(home.data?.groups ?? []) { g in
                GroupCard(group: g, onAsk: { askGroup = g }, onJoin: { router.open(path: "/meeting/lesson/\($0)") }, onHomework: { path.append(.group(g.id)) })
                    .contentShape(Rectangle())
                    .onTapGesture { path.append(.group(g.id)) }
            }
        }
        .navigationTitle("כל הקבוצות")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $askGroup) { group in
            AskTeacherSheet(group: group) { Task { await home.load() } }
                .presentationDetents([.medium]).presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

@MainActor
final class PastLessonsModel: ObservableObject {
    struct Item: Identifiable { let id: String; let lesson: GroupDetail.Past; let groupTitle: String }
    @Published private(set) var items: [Item] = []
    @Published private(set) var loading = true

    func load(_ groups: [StudentHome.Group]) async {
        var all: [Item] = []
        await withTaskGroup(of: [Item].self) { tasks in
            for g in groups {
                tasks.addTask {
                    let key = "group-\(g.id)"
                    var detail: GroupDetail?
                    if let raw = try? await API.request("GET", "/api/native/student/group/\(g.id)") {
                        detail = try? API.decoder.decode(GroupDetail.self, from: raw)
                        LocalCache.write(key, raw)
                    } else if let raw = LocalCache.read(key) {
                        detail = try? API.decoder.decode(GroupDetail.self, from: raw)
                    }
                    return (detail?.past ?? []).map { Item(id: $0.id, lesson: $0, groupTitle: g.title) }
                }
            }
            for await part in tasks { all += part }
        }
        items = all.sorted { $0.lesson.scheduledAt > $1.lesson.scheduledAt }
        loading = false
    }
}

struct PastLessonsView: View {
    @EnvironmentObject private var home: HomeModel
    @StateObject private var model = PastLessonsModel()

    var body: some View {
        Scaffold(maxWidth: 720) {
            if model.loading && model.items.isEmpty {
                ProgressView().padding(.top, 40)
            } else if model.items.isEmpty {
                EmptyState(pose: .sit, title: "עוד לא היו שיעורים", message: "אחרי השיעור הראשון תוכלו לראות כאן מה למדתם ומה היה שיעורי הבית.")
            } else {
                ForEach(model.items) { PastLessonRow(lesson: $0.lesson, groupTitle: $0.groupTitle) }
            }
        }
        .navigationTitle("שיעורים קודמים")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await model.load(home.data?.groups ?? []) }
    }
}

// MARK: - Sheets

/// A question for the teacher, before the lesson. Goes to the same place as the website's version.
struct AskTeacherSheet: View {
    let group: StudentHome.Group
    var onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("שאלה ל\(group.teacher ?? "מורה")").font(.heebo(22, 800)).foregroundStyle(Theme.ink)
            Text("המורה רואה את זה כשהוא מתכונן לשיעור הבא של \(group.title).").font(.heebo(14, 500)).foregroundStyle(Theme.slate600)
            TextField("מה תקוע? מה תרצו שנעבור?", text: $text, axis: .vertical)
                .lineLimit(3...8).font(.heebo(17, 500)).focused($focused)
                .padding(14)
                .background(Theme.slate50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let error { Text(error).font(.heebo(13, 600)).foregroundStyle(Theme.rose600) }
            Button { Task { await send() } } label: {
                HStack { if sending { ProgressView().tint(.white) }; Text("שליחה למורה") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear { focused = true }
    }

    private func send() async {
        sending = true; error = nil
        defer { sending = false }
        do {
            _ = try await API.request("POST", "/api/native/student/lesson-question",
                                      json: ["groupId": group.id, "lessonId": group.nextLesson()?.id ?? NSNull(), "text": text])
            onSent()
            dismiss()
        } catch { self.error = "לא הצלחנו לשלוח. נסו שוב." }
    }
}

/// The parent's WhatsApp number, as on the website.
struct ParentSheet: View {
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("חיבור הורה").font(.heebo(22, 800)).foregroundStyle(Theme.ink)
            Text("נשלח להורה הודעת וואטסאפ עם עדכונים על השיעורים והצריכה. ההורה גם מנהל את התשלום והתקרה החודשית.")
                .font(.heebo(14, 500)).foregroundStyle(Theme.slate600)
            LugiFieldBox(label: "מספר וואטסאפ של ההורה", focused: focused) {
                TextField("050-123-4567", text: $phone)
                    .keyboardType(.numberPad).font(.heebo(20, 600).monospacedDigit())
                    .environment(\.layoutDirection, .leftToRight).multilineTextAlignment(.leading)
                    .focused($focused)
                    .onChange(of: phone) { _, new in let f = Phone.format(new); if f != new { phone = f } }
            }
            if let error { Text(error).font(.heebo(13, 600)).foregroundStyle(Theme.rose600) }
            Button { Task { await save() } } label: { HStack { if busy { ProgressView().tint(.white) }; Text("שמירה") } }
                .buttonStyle(PrimaryButtonStyle()).disabled(!Phone.isValid(phone) || busy)
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear { focused = true }
    }

    private func save() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await API.request("POST", "/api/native/student/parent", json: ["phone": Phone.digits(phone)])
            onSaved()
            dismiss()
        } catch APIError.server(_, let message) where !message.isEmpty {
            error = message
        } catch { self.error = "לא הצלחנו לשמור. נסו שוב." }
    }
}
