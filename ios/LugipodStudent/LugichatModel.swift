import SwiftUI
import UIKit

struct ChatMessage: Identifiable, Equatable {
    enum Role { case student, bot }
    let id = UUID()
    let role: Role
    var body: String
}

/// One Lugichat conversation about one photographed question. The server keeps nothing: every turn re-sends the photo and the
/// thread (POST /api/student/guided-solve, with the app's bearer token).
@MainActor
final class LugichatModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var image: UIImage?
    @Published private(set) var sending = false
    @Published var error: String?
    /// The free answers of the day (and any pack) are used up.
    @Published private(set) var limitHit = false
    @Published private(set) var quota: Quota?
    @Published var subjectId: String?

    private var imageBase64 = ""

    var hasThread: Bool { image != nil || !messages.isEmpty }
    /// The last turn failed (a student message or the photo is waiting for an answer).
    var canRetry: Bool { error != nil && !sending && (messages.last?.role == .student || messages.isEmpty) && hasThread }

    #if DEBUG
    func loadPreview(_ sample: (messages: [ChatMessage], limit: Bool)) {
        messages = sample.messages
        limitHit = sample.limit
    }
    #endif

    func reset() {
        messages = []; image = nil; imageBase64 = ""; error = nil; limitHit = false
    }

    func start(with picture: UIImage) {
        reset()
        image = picture
        imageBase64 = Self.encode(picture)
        Task { await send(nil) }
    }

    func send(_ text: String?) async {
        guard !sending else { return }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { messages.append(ChatMessage(role: .student, body: trimmed)) }
        guard hasThread else { return }
        sending = true; error = nil
        defer { sending = false }
        let payload: [String: Any] = [
            "imageBase64": imageBase64,
            "mimeType": "image/jpeg",
            "subjectId": subjectId ?? NSNull(),
            "messages": messages.map { ["role": $0.role == .student ? "student" : "bot", "body": $0.body] },
        ]
        do {
            let data = try await API.request("POST", "/api/student/guided-solve", json: payload, timeout: 75)
            let reply = try API.decoder.decode(Reply.self, from: data)
            messages.append(ChatMessage(role: .bot, body: reply.answer))
            if let q = reply.quota { quota = q }
        } catch APIError.server(let status, _) where status == 402 {
            limitHit = true
            // The unanswered student message stays in the thread, so nothing the student wrote is lost.
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
    static func encode(_ image: UIImage) -> String {
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
}
