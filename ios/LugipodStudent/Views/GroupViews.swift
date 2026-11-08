import PhotosUI
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
    @State private var asking = false

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
            VStack(spacing: 12) {
                Button { asking = true } label: { Label("שאלה חדשה (אפשר גם תמונה)", systemImage: "camera.fill") }
                    .buttonStyle(SoftButtonStyle(fg: .white, bg: tint.accent))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(model.detail?.questions ?? []) { q in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: q.hasImage ? "photo.fill" : "text.bubble.fill").foregroundStyle(tint.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.text.isEmpty ? "שאלה עם תמונה" : q.text).font(.heebo(14, 600)).foregroundStyle(Theme.ink)
                            Text("נשלחה למורה · \(HebrewDate.relative(q.createdAt))").font(.heebo(11, 500)).foregroundStyle(Theme.slate400)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .card(padding: 14, radius: 18)
        }
        .sheet(isPresented: $asking) {
            AskTeacherSheet(group: group) {
                Task { await model.load(groupId); await home.load() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .environment(\.layoutDirection, .rightToLeft)
        }
    }

    @ViewBuilder private var past: some View {
        VStack(spacing: 8) {
            SectionTitle(text: "לשיעורים קודמים", count: model.detail?.past.count)
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
            FileButtons(files: lesson.files ?? [])
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
        .navigationTitle("לשיעורים קודמים")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await model.load(home.data?.groups ?? []) }
    }
}

// MARK: - Sheets

/// A question for the teacher, before the lesson: text and/or a photo (camera, gallery, or pasted from the clipboard). Goes to the same place
/// as the website's version, where it is also solved for the teacher (and only the teacher).
struct AskTeacherSheet: View {
    let group: StudentHome.Group
    var onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var sending = false
    @State private var error: String?
    @State private var sent = false
    @FocusState private var focused: Bool

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var canSend: Bool { !sending && (image != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sent {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Theme.emerald500)
                    Text("נשלח ל\(group.teacher ?? "מורה") ✓").font(.heebo(22, 800)).foregroundStyle(Theme.ink)
                    Text("המורה יראה את השאלה לפני השיעור, כבר עם פתרון מוכן.").font(.heebo(15, 500)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.top, 40)
                Spacer(minLength: 0)
            } else {
                Text("שאלה ל\(group.teacher ?? "מורה")").font(.heebo(22, 800)).foregroundStyle(Theme.ink)
                Text("המורה רואה את זה כשהוא מתכונן לשיעור הבא של \(group.title).").font(.heebo(14, 500)).foregroundStyle(Theme.slate600)
                TextField("מה תקוע? מה תרצו שנעבור?", text: $text, axis: .vertical)
                    .lineLimit(3...8).font(.heebo(17, 500)).focused($focused)
                    .padding(14)
                    .background(Theme.slate50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let image {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Button { self.image = nil } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white, Theme.slate700)
                        }
                        .offset(x: -8, y: -8)
                        .accessibilityLabel("הסרת התמונה")
                    }
                }
                HStack(spacing: 10) {
                    if cameraAvailable {
                        Button { showCamera = true } label: { Label("צילום", systemImage: "camera.fill") }.buttonStyle(SoftButtonStyle())
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label("גלריה", systemImage: "photo.on.rectangle") }
                        .font(.heebo(14, 700)).foregroundStyle(Theme.brand700)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(Theme.brand50, in: Capsule())
                    // "Copy" a picture anywhere on the phone (a screenshot, a photo, a web page) and paste it here.
                    if UIPasteboard.general.hasImages {
                        Button { image = UIPasteboard.general.image } label: { Label("הדבקה", systemImage: "doc.on.clipboard") }.buttonStyle(SoftButtonStyle())
                    }
                }
                if let error { Text(error).font(.heebo(13, 600)).foregroundStyle(Theme.rose600) }
                Button { Task { await send() } } label: {
                    HStack { if sending { ProgressView().tint(.white) }; Text("שליחה למורה") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSend)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { image = $0 }.ignoresSafeArea() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { image = img }
                pickerItem = nil
            }
        }
        .onAppear { focused = true }
    }

    private func send() async {
        sending = true; error = nil
        defer { sending = false }
        var body: [String: Any] = ["groupId": group.id, "lessonId": group.nextLesson()?.id ?? NSNull(), "text": text]
        if let image { body["imageBase64"] = LugichatModel.encode(image); body["mimeType"] = "image/jpeg" }
        do {
            _ = try await API.request("POST", "/api/native/student/lesson-question", json: body, timeout: 60)
            onSent()
            sent = true
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            dismiss()
        } catch APIError.server(_, let message) where !message.isEmpty {
            error = message
        } catch { self.error = "לא הצלחנו לשלוח. בדקו חיבור ונסו שוב." }
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
                PhoneField(phone: $phone, focused: $focused)
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
