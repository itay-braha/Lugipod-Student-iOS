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
        messages = []; pending = nil; imageBase64 = ""; error = nil; limitHit = false; pack = .idle
    }

    func send(_ text: String) async {
        guard !sending else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || pending != nil else { return }
        if let img = pending { imageBase64 = Self.encode(img) }
        messages.append(ChatMessage(role: .student, body: trimmed, image: pending))
        pending = nil
        await run()
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
        do {
            let data = try await API.request("POST", "/api/student/guided-solve", json: payload, timeout: 75)
            let reply = try API.decoder.decode(Reply.self, from: data)
            messages.append(ChatMessage(role: .bot, body: reply.answer))
            if let q = reply.quota { quota = q }
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
    }

    private struct Reply: Decodable {
        let answer: String
        let quota: Quota?
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
