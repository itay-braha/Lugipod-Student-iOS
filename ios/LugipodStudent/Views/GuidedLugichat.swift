import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Guided mode from Lugichat (website: docs/SOLUTIONS_EVERYWHERE.md §4–§5). Under Lugi's first answer to a question: "יאללה, מתחילים 🦊"
/// turns the typed or photographed question into one of ours with a stored solution and opens it in the guided player (every step closed,
/// the student's tries checked by Lugi, the drawing lighting up). 📄 takes a whole PDF / Word worksheet: a numbered list of its exercises,
/// one tap starts that one. The day's guided solutions used up → the offer card (lugis only, consumption under the family's limit, like the
/// Lugichat pack: no price in money, no payment).
@MainActor
final class GuidedFlow: ObservableObject {
    struct Offer: Decodable, Identifiable, Equatable {
        let kind: String
        let lugis: Double
        let perDay: Int
        let days: Int
        let best: Bool?
        var id: String { kind }
        var name: String { kind == "starter" ? "חבילת פתיחה" : kind == "week" ? "חבילת שבוע" : "שבוע מבחן" }
        var lugisText: String { lugis == lugis.rounded() ? String(Int(lugis)) : String(format: "%.1f", lugis) }
    }
    struct Status: Decodable, Equatable {
        let freePerDay: Int?
        let freeReason: String?
        let canStart: Bool?
        let messagesIncluded: Int?
        let offers: [Offer]?
    }
    struct FileItem: Decodable, Identifiable, Equatable {
        let n: Int
        let label: String?
        let page: Int?
        let text: String
        var id: Int { n }
    }

    enum Card: Equatable { case idle, busy, failed(String), parent(String), wrong }
    /// Lugi read the question and shows it back first ("זו השאלה?", as on the website); the session starts on "כן".
    struct Prepared: Equatable {
        let questionId: String
        let prompt: String
        let choices: [String]
        let figureSvg: String?
    }
    @Published var confirm: Prepared?
    /// The start card under the first answer (per conversation: the first student message's id).
    @Published var card: Card = .idle
    @Published var dismissed: Set<UUID> = []
    /// The offer sheet (the day's guided solutions are used up) and what to retry after a pack is taken.
    @Published var offer: Status?
    @Published var buying: String?
    @Published var offerError: String?
    private var retry: (() async -> Void)?
    /// The worksheet sheet: reading the file, its exercises, the one being prepared.
    @Published var fileOpen = false
    @Published var fileBusy = false
    @Published var fileName = ""
    @Published var fileId: String?
    @Published var fileItems: [FileItem] = []
    @Published var fileError: String?
    @Published var preparing: Int?

    /// The guided player for a question (a website page inside the app, like the daily challenge's solution).
    var onOpen: ((String) -> Void)?

    // MARK: start

    func start(text: String, image: UIImage?) async {
        guard card != .busy else { return }
        card = .busy
        confirm = nil
        // read and show back first: nothing is used until the student says it is the question (the solving starts now, though)
        var body: [String: Any] = ["text": text, "prepare": true]
        if let image {
            body["imageBase64"] = await Task.detached { LugichatModel.encode(image) }.value
            body["mimeType"] = "image/jpeg"
        }
        await post(body) { [weak self] in await self?.start(text: text, image: image) }
    }

    /// "כן, זו השאלה": the session starts and the guided player opens.
    func confirmStart() async {
        guard let c = confirm, card != .busy else { return }
        card = .busy
        await post(["questionId": c.questionId]) { [weak self] in await self?.confirmStart() }
    }

    /// "לא בדיוק": the student writes what is different or photographs it again.
    func notThisOne() {
        confirm = nil
        card = .wrong
    }

    private func post(_ body: [String: Any], again: @escaping () async -> Void) async {
        struct Reply: Decodable { let ok: Bool?; let sessionId: String?; let questionId: String?; let prepared: Bool?; let prompt: String?; let choices: [String]?; let figureSvg: String? }
        do {
            let data = try await API.request("POST", "/api/student/guided/start", json: body, timeout: 240)
            let r = try API.decoder.decode(Reply.self, from: data)
            card = .idle
            preparing = nil
            if r.prepared == true, let q = r.questionId {
                confirm = Prepared(questionId: q, prompt: r.prompt ?? "", choices: r.choices ?? [], figureSvg: r.figureSvg)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            if let q = r.questionId, let s = r.sessionId {
                confirm = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                fileOpen = false
                onOpen?("/solution/\(q)?guided=\(s)&app=1")
            } else { card = .failed("לא הצלחנו להתחיל כרגע. נסו שוב.") }
        } catch APIError.server(402, _) {
            card = .idle
            preparing = nil
            retry = again
            await loadStatus()
        } catch APIError.server(403, let message) where message.contains("הורה") {
            card = .parent(message)
            preparing = nil
        } catch APIError.server(_, let message) where !message.isEmpty {
            card = .failed(message)
            if preparing != nil { fileError = message }
            preparing = nil
        } catch APIError.notSignedIn {
            await AuthStore.shared.sessionLost("GuidedLugichat")
        } catch {
            card = .failed("אין חיבור כרגע. נסו שוב בעוד רגע.")
            preparing = nil
        }
    }

    private func loadStatus() async {
        struct Reply: Decodable { let status: Status? }
        if let data = try? await API.request("GET", "/api/student/guided/status"), let r = try? API.decoder.decode(Reply.self, from: data), let s = r.status {
            offerError = nil
            offer = s
        } else {
            card = .failed("לוגי לא הצליח לפתוח את הפתרון כרגע. נסו שוב בעוד רגע.")
        }
    }

    func buy(_ kind: String) async {
        guard buying == nil else { return }
        buying = kind
        offerError = nil
        defer { buying = nil }
        do {
            _ = try await API.request("POST", "/api/student/guided/buy", json: ["kind": kind], timeout: 30)
            offer = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let again = retry { retry = nil; await again() }
        } catch APIError.server(_, let message) {
            offerError = message.isEmpty ? "לא הצלחנו כרגע. נסו שוב." : message
        } catch {
            offerError = "אין חיבור כרגע. נסו שוב בעוד רגע."
        }
    }

    // MARK: a whole worksheet

    func read(file url: URL) async {
        fileOpen = true
        fileBusy = true
        fileError = nil
        fileItems = []
        fileId = nil
        fileName = url.lastPathComponent
        defer { fileBusy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { fileError = "לא הצלחנו לפתוח את הקובץ."; return }
        guard data.count <= 3_000_000 else { fileError = "הקובץ גדול מדי (עד כ‑3MB). אפשר לצלם את השאלה עצמה."; return }
        let isPdf = url.pathExtension.lowercased() == "pdf"
        let mime = isPdf ? "application/pdf" : "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        struct Reply: Decodable { let fileId: String?; let questions: [FileItem]? }
        do {
            let reply = try await API.request("POST", "/api/student/guided/file",
                                              json: ["fileBase64": data.base64EncodedString(), "mimeType": mime, "name": url.lastPathComponent], timeout: 240)
            let r = try API.decoder.decode(Reply.self, from: reply)
            fileId = r.fileId
            fileItems = r.questions ?? []
            if fileItems.isEmpty { fileError = "לא מצאנו בקובץ תרגילים." }
        } catch APIError.server(_, let message) where !message.isEmpty {
            fileError = message
        } catch APIError.notSignedIn {
            await AuthStore.shared.sessionLost("GuidedLugichat")
        } catch {
            fileError = "לא הצלחנו לעבור על הקובץ הפעם. נסו שוב."
        }
    }

    func startFileItem(_ n: Int) async {
        guard let fileId, preparing == nil else { return }
        preparing = n
        fileError = nil
        await post(["fileId": fileId, "n": n]) { [weak self] in await self?.startFileItem(n) }
    }
}

/// Under Lugi's first answer: one big orange button.
struct GuidedStartCard: View {
    @ObservedObject var flow: GuidedFlow
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        if let c = flow.confirm {
            confirmCard(c)
        } else if flow.card == .wrong {
            Text("🦊 אין בעיה. כתבו לי מה שונה בשאלה, או צלמו אותה שוב קרוב יותר, ואכין אותה מחדש.")
                .font(.heebo(14, 600)).foregroundStyle(Theme.slate700).fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
        } else {
            startCard
        }
    }

    /// "זו השאלה?" — the question as Lugi read it (its drawing redrawn in our style), before anything starts.
    private func confirmCard(_ c: GuidedFlow.Prepared) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Lugi(pose: .ponder, height: 44)
                Text("זו השאלה?").font(.heebo(17, 900)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let svg = c.figureSvg, !svg.isEmpty {
                    FigureSVG(svg: svg).frame(height: 200).frame(maxWidth: .infinity)
                }
                RichText(text: c.prompt, font: .heebo(15, 600))
                ForEach(Array(c.choices.enumerated()), id: \.offset) { i, choice in
                    RichText(text: "\(i + 1). \(choice)", font: .heebo(14, 500), color: Theme.slate600)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
            if case .failed(let message) = flow.card {
                Text(message).font(.heebo(13, 700)).foregroundStyle(Theme.rose600)
            }
            HStack(spacing: 8) {
                Button { Task { await flow.confirmStart() } } label: {
                    HStack(spacing: 6) {
                        if flow.card == .busy { ProgressView().tint(.white) }
                        Text(flow.card == .busy ? "פותח…" : "כן, יאללה מתחילים 🦊").font(.heebo(16, 900)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Theme.orange500, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Theme.orange500.opacity(0.35), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(flow.card == .busy)
                .accessibilityIdentifier("guided-confirm")
                Button("לא בדיוק") { flow.notThisOne() }.font(.heebo(14, 700)).foregroundStyle(Theme.slate500).padding(.horizontal, 8)
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(hex: 0xFFF7ED), .white], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.orange300, lineWidth: 1))
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Lugi(pose: flow.card == .busy ? .search : .wave, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(flow.card == .busy ? "לוגי קורא את השאלה…" : "שלוגי ידריך אותך בשאלה הזו, שלב אחר שלב?")
                        .font(.heebo(16, 800)).foregroundStyle(Theme.ink)
                    Text(flow.card == .busy ? "עוד רגע אראה לכם אותה, כדי לוודא שהבנתי נכון." : "אתם פותרים, לוגי בודק כל צעד, עם שרטוט ומטרה לכל שלב.")
                        .font(.heebo(13, 500)).foregroundStyle(Theme.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            switch flow.card {
            case .failed(let message):
                Text(message).font(.heebo(13, 700)).foregroundStyle(Theme.rose600)
            case .parent(let message):
                Text(message).font(.heebo(13, 700)).foregroundStyle(Theme.slate700)
                Button("💬 שליחה להורה בוואטסאפ") { UIApplication.shared.open(LugichatView.parentInviteURL) }.buttonStyle(SoftButtonStyle())
            default: EmptyView()
            }
            if flow.card != .busy {
                HStack(spacing: 8) {
                    Button(action: onStart) {
                        Text("יאללה, מתחילים 🦊").font(.heebo(16, 900)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Theme.orange500, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Theme.orange500.opacity(0.35), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guided-start")
                    Button("לא עכשיו", action: onDismiss).font(.heebo(14, 700)).foregroundStyle(Theme.slate500).padding(.horizontal, 8)
                }
            } else {
                ProgressView().tint(Theme.orange500).frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(hex: 0xFFF7ED), .white], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.orange300, lineWidth: 1))
    }
}

/// The day's guided solutions are used: the generous offers, in lugis (consumption under the family's monthly limit).
struct GuidedOfferSheet: View {
    @ObservedObject var flow: GuidedFlow
    let status: GuidedFlow.Status

    // never what we gave or why it stopped (founder 2026-11-22): the invitation to continue and what it comes with
    private var tomorrow: String {
        status.freeReason == "ceiling" ? "" : "או שממשיכים מחר. "
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Lugi(pose: .wave, height: 70)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ממשיכים עם לוגי? 🦊").font(.heebo(20, 900)).foregroundStyle(Theme.ink)
                        Text("\(tomorrow)החבילה נספרת בצריכה החודשית של המשפחה.").font(.heebo(14, 500)).foregroundStyle(Theme.slate600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(status.offers ?? []) { o in
                    Button { Task { await flow.buy(o.kind) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(o.name).font(.heebo(17, 900)).foregroundStyle(Theme.ink)
                                Spacer()
                                if o.kind == "starter" || o.best == true {
                                    Text(o.kind == "starter" ? "פעם אחת בלבד" : "הכי משתלם").font(.heebo(11, 900)).foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.orange500, in: Capsule())
                                }
                            }
                            Text("עוד \(o.perDay) פתרונות מודרכים בכל יום · \(o.days) ימים").font(.heebo(14, 600)).foregroundStyle(Theme.slate600)
                            HStack(spacing: 6) {
                                if flow.buying == o.kind { ProgressView().tint(Theme.orange500) }
                                Text("\(o.lugisText) לוגי").font(.heebo(17, 900)).foregroundStyle(Color(hex: 0xC2410C))
                            }
                            .padding(.top, 2)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(o.kind == "starter" || o.best == true ? Theme.orange300 : Theme.slate200, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(flow.buying != nil)
                }
                if let e = flow.offerError {
                    Text(e).font(.heebo(13, 700)).foregroundStyle(Theme.rose600).fixedSize(horizontal: false, vertical: true)
                }
                Text("כל פתרון מודרך כולל שיחה עם לוגי. הלוגי נספרים בצריכה החודשית של המשפחה.")
                    .font(.heebo(12, 500)).foregroundStyle(Theme.slate500).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(ScreenBackground())
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium, .large])
    }
}

/// A whole worksheet: its exercises, one tap → that one, guided.
struct FileQuestionsSheet: View {
    @ObservedObject var flow: GuidedFlow

    var body: some View {
        NavigationStack {
            Group {
                if flow.fileBusy {
                    VStack(spacing: 14) {
                        Lugi(pose: .search, height: 90)
                        Text("לוגי עובר על הקובץ…").font(.heebo(17, 800)).foregroundStyle(Theme.ink)
                        Text("קובץ ארוך לוקח עד דקה. קובץ שכבר הועלה נפתח מיד.").font(.heebo(13, 500)).foregroundStyle(Theme.slate500)
                        ProgressView().tint(Theme.violet500)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if let e = flow.fileError {
                                Text(e).font(.heebo(14, 700)).foregroundStyle(Theme.rose600).fixedSize(horizontal: false, vertical: true)
                            }
                            if !flow.fileItems.isEmpty {
                                Text("באיזה תרגיל מתחילים?").font(.heebo(18, 900)).foregroundStyle(Theme.ink)
                            }
                            ForEach(flow.fileItems) { item in
                                Button { Task { await flow.startFileItem(item.n) } } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(item.n)").font(.heebo(15, 900)).foregroundStyle(.white)
                                            .frame(width: 30, height: 30).background(Theme.violet500, in: Circle())
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text([item.label, item.page.map { "עמוד \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                                .font(.heebo(12, 700)).foregroundStyle(Theme.slate500)
                                            Text(item.text).font(.heebo(14, 600)).foregroundStyle(Theme.ink).lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 0)
                                        if flow.preparing == item.n { ProgressView().tint(Theme.orange500) }
                                    }
                                    .padding(12)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(flow.preparing != nil)
                            }
                            if flow.preparing != nil {
                                Text("לוגי מכין את הפתרון לתרגיל הזה… בפעם הראשונה זה לוקח עד דקה.")
                                    .font(.heebo(13, 600)).foregroundStyle(Theme.slate500)
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .background(ScreenBackground())
            .navigationTitle(flow.fileName.isEmpty ? "📄 דף עבודה" : "📄 \(flow.fileName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("סגירה") { flow.fileOpen = false } }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// The question's drawing (our own SVG, sanitized by the server) in a small non-scrolling web view.
struct FigureSVG: UIViewRepresentable {
    let svg: String

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.loadHTMLString(Self.page(svg), baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func page(_ svg: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:transparent;display:flex;align-items:center;justify-content:center}
        svg{max-width:100%;max-height:100%;height:auto;width:auto}</style></head><body>\(svg)</body></html>
        """
    }
}

/// The system file picker for a PDF or Word worksheet.
struct WorksheetPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let docx = UTType(filenameExtension: "docx") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, docx], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
