import SwiftUI
import UIKit

struct ChatMessage: Identifiable, Equatable {
    enum Role { case student, bot }
    let id = UUID()
    let role: Role
    var body: String
    var image: UIImage? = nil
}

/// One Lugichat conversation. The server keeps nothing: every turn re-sends the latest photo and the thread
/// (POST /api/student/guided-solve, with the app's bearer token). The student never picks a subject: the server reads it from the
/// question and from the groups the student is in.
@MainActor
final class LugichatModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    /// A photo attached to the message being written.
    @Published var pending: UIImage?
    @Published private(set) var sending = false
    @Published var error: String?
    /// The free answers (and any pack) are used up.
    @Published private(set) var limitHit = false
    @Published private(set) var quota: Quota?
    /// The saved conversation on screen (nil = a new one that is not saved yet), and the list of the student's conversations.
    @Published private(set) var chatId: String?
    @Published private(set) var chats: [ChatSummary] = []
    @Published private(set) var opening = false
    /// Saving runs one step after another, so the answer is never saved before the question that created the conversation.
    private var saveTail: Task<Void, Never>?
    /// Going on after the free answers: what the student is looking at. Consumption, never a payment: the lugis count in their usage.
    enum Pack: Equatable { case idle, buying, capReached, parentTold, failed(String) }
    @Published private(set) var pack: Pack = .idle

    private var imageBase64 = ""
    /// Which of the welcome lines is shown (picked once per app launch, so it does not flicker).
    let greetingSeed = Int.random(in: 0..<1000)

    var hasThread: Bool { !messages.isEmpty }
    /// The last turn failed: there is a student message still waiting for its answer.
    var canRetry: Bool { error != nil && !sending && messages.last?.role == .student }

    /// Only when the student is close to running out do we say anything about it (never the daily figure).
    var runningLow: Int? {
        guard let r = quota?.remaining, r <= 3, r > 0 else { return nil }
        return r
    }

    #if DEBUG
    func loadPreview(_ sample: (messages: [ChatMessage], limit: Bool)) {
        messages = sample.messages
        limitHit = sample.limit
        if sample.limit { quota = Quota(freeLeft: 0, freePerDay: nil, packLeft: 0, canAsk: false) } else { quota = Quota(freeLeft: 2, freePerDay: nil, packLeft: 0, canAsk: true) }
    }
    #endif

    func reset() {
        messages = []; pending = nil; imageBase64 = ""; error = nil; limitHit = false; pack = .idle; chatId = nil
    }

    func send(_ text: String) async {
        guard !sending else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || pending != nil else { return }
        if let img = pending { imageBase64 = Self.encode(img) }
        let sentImage = pending != nil ? imageBase64 : nil
        messages.append(ChatMessage(role: .student, body: trimmed, image: pending))
        pending = nil
        save(role: "student", body: trimmed, imageBase64: sentImage)
        await run()
    }

    // MARK: Saved conversations

    /// Saves one message of the conversation on the server (the first student message creates it). Best effort: a failed save never
    /// disturbs the conversation on screen.
    private func save(role: String, body: String, imageBase64: String?) {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        let previous = saveTail
        saveTail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            var payload: [String: Any] = ["role": role, "body": body]
            if let imageBase64 { payload["imageBase64"] = imageBase64; payload["mimeType"] = "image/jpeg" }
            do {
                if let id = self.chatId {
                    _ = try await API.post("/api/native/student/chats/\(id)/messages", json: payload)
                } else if role == "student" {
                    struct Created: Decodable { let id: String }
                    var first: [String: Any] = ["text": body]
                    if let imageBase64 { first["imageBase64"] = imageBase64; first["mimeType"] = "image/jpeg" }
                    let data = try await API.post("/api/native/student/chats", json: first)
                    self.chatId = try API.decoder.decode(Created.self, from: data).id
                    await self.refreshChats()
                }
            } catch { /* not saved: the chat on screen carries on */ }
        }
    }

    func refreshChats() async {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        struct Reply: Decodable { let chats: [ChatSummary] }
        if let data = try? await API.request("GET", "/api/native/student/chats"), let reply = try? API.decoder.decode(Reply.self, from: data) {
            chats = reply.chats
        }
    }

    /// Opens a saved conversation, pictures included. `answerPending`: the student shared a picture into it from another app (the Share
    /// extension), so when the last message is theirs and unanswered, Lugifox answers it now.
    func open(chatId id: String, answerPending: Bool = false) async {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        guard !sending else { return }
        opening = true
        defer { opening = false }
        struct Msg: Decodable { let role: String; let body: String; let imageUrl: String? }
        struct Chat: Decodable { let id: String; let messages: [Msg] }
        do {
            let data = try await API.request("GET", "/api/native/student/chats/\(id)")
            let chat = try API.decoder.decode(Chat.self, from: data)
            var list: [ChatMessage] = []
            var lastImage: UIImage?
            for m in chat.messages {
                var image: UIImage?
                if let link = m.imageUrl, let url = URL(string: link), let got = try? await URLSession.shared.data(from: url) { image = UIImage(data: got.0) }
                if image != nil { lastImage = image }
                list.append(ChatMessage(role: m.role == "student" ? .student : .bot, body: m.body, image: image))
            }
            messages = list
            chatId = chat.id
            pending = nil; error = nil; limitHit = false; pack = .idle
            imageBase64 = lastImage.map { Self.encode($0) } ?? ""
            if answerPending, messages.last?.role == .student { await run() }
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            self.error = "לא הצלחנו לפתוח את השיחה. נסו שוב."
        }
    }

    func deleteChat(_ id: String) async {
        _ = try? await API.request("DELETE", "/api/native/student/chats/\(id)")
        chats.removeAll { $0.id == id }
        if chatId == id { reset() }
    }

    func retry() async { await run() }

    /// "Go on now": takes the next block of answers (the server draws its lugis through the family's cap like any lesson).
    func buyPack() async {
        guard pack != .buying else { return }
        pack = .buying
        struct Reply: Decodable { let ok: Bool?; let error: String?; let capReached: Bool?; let quota: Quota? }
        do {
            let data = try await API.request("POST", "/api/native/student/lugichat-pack", json: [:], timeout: 30)
            let reply = try API.decoder.decode(Reply.self, from: data)
            if let q = reply.quota { quota = q }
            limitHit = false
            pack = .idle
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch APIError.server(_, let message) {
            // The family has no room left under its limit: say so and offer the one thing that helps.
            pack = message.contains("תקרה") ? .capReached : .failed(message.isEmpty ? "לא הצלחנו כרגע. נסו שוב." : message)
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch { pack = .failed("לא הצלחנו כרגע. בדקו חיבור ונסו שוב.") }
    }

    /// The family limit is reached: send the parent our message with the details (same as the home banner).
    func tellParent() async {
        pack = .buying
        do {
            _ = try await API.request("POST", "/api/native/student/cap-request", json: [:], timeout: 30)
            pack = .parentTold
        } catch APIError.server(_, let message) where !message.isEmpty {
            pack = .failed(message)
        } catch { pack = .failed("לא הצלחנו לשלוח. בדקו חיבור ונסו שוב.") }
    }

    private func run() async {
        guard !sending else { return }
        sending = true; error = nil
        defer { sending = false }
        let thread = messages.filter { !$0.body.isEmpty }
        let payload: [String: Any] = [
            "imageBase64": imageBase64,
            "mimeType": "image/jpeg",
            "messages": thread.map { ["role": $0.role == .student ? "student" : "bot", "body": $0.body] },
        ]
        // The tutor's words appear while they are written (server-sent events); the closing event carries the complete answer and the
        // quota and replaces what was streamed. A failed turn takes the half-written answer back.
        var streamedIndex: Int?
        var streamed = ""
        var finished: (answer: String, quota: Quota?)?
        var streamError: (status: Int, message: String)?
        do {
            try await API.stream("/api/student/guided-solve", json: payload) { [self] event in
                switch event["t"] as? String {
                case "delta":
                    streamed += event["text"] as? String ?? ""
                    if let i = streamedIndex { messages[i].body = streamed }
                    else { messages.append(ChatMessage(role: .bot, body: streamed)); streamedIndex = messages.count - 1 }
                case "done":
                    var q: Quota?
                    if let qo = event["quota"], JSONSerialization.isValidJSONObject(qo), let d = try? JSONSerialization.data(withJSONObject: qo) {
                        q = try? API.decoder.decode(Quota.self, from: d)
                    }
                    finished = (event["answer"] as? String ?? "", q)
                case "error":
                    streamError = (event["status"] as? Int ?? 502, event["error"] as? String ?? "")
                default: break
                }
            }
            if let i = streamedIndex, finished == nil { messages.remove(at: i); streamedIndex = nil }
            if let e = streamError { throw APIError.server(e.status, e.message) }
            guard let finished, !finished.answer.isEmpty else { throw APIError.server(502, "") }
            if let i = streamedIndex { messages[i].body = finished.answer } else { messages.append(ChatMessage(role: .bot, body: finished.answer)) }
            save(role: "bot", body: finished.answer, imageBase64: nil)
            if let q = finished.quota { quota = q }
        } catch APIError.server(let status, _) where status == 402 {
            limitHit = true
            quota = Quota(freeLeft: 0, freePerDay: nil, packLeft: 0, canAsk: false)
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch APIError.server(_, let message) where !message.isEmpty {
            error = message
        } catch {
            self.error = "לא הצלחנו לקבל תשובה. בדקו חיבור ונסו שוב."
        }
        // a turn that failed (also a connection lost halfway) takes back the half-written answer
        if error != nil || limitHit, finished == nil, let i = streamedIndex, i < messages.count, messages[i].role == .bot { messages.remove(at: i) }
    }

    /// Longest side 1600 px, JPEG: sharp enough to read handwriting, small enough to send over mobile data.
    nonisolated static func encode(_ image: UIImage) -> String {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return (resized.jpegData(compressionQuality: 0.8) ?? Data()).base64EncodedString()
    }

    /// A welcome line that changes from visit to visit, so it feels like someone is there.
    func greeting(name: String, now: Date = Date()) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        let hour = Calendar.current.component(.hour, from: now)
        let part = hour < 5 ? "לילה טוב" : hour < 12 ? "בוקר טוב" : hour < 18 ? "צהריים טובים" : "ערב טוב"
        let lines = [
            first.isEmpty ? "במה נתקדם היום?" : "במה נתקדם היום, \(first)?",
            first.isEmpty ? part : "\(part), \(first)",
            "מה תקוע לכם היום?",
            "איזה תרגיל נפתור יחד?",
            "בואו נבין את זה ביחד",
            first.isEmpty ? "מה על הפרק?" : "מה על הפרק, \(first)?",
        ]
        return lines[greetingSeed % lines.count]
    }
}

/// One row of "my conversations".
struct ChatSummary: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let lastAt: Date
    let snippet: String
    let hasImage: Bool
}
