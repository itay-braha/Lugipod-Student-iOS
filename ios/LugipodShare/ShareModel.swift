import SwiftUI
import UIKit

/// A group the student can send a pre-lesson question to, with its next (or running) lesson.
struct ShareGroup: Identifiable, Decodable, Equatable {
    struct Lesson: Decodable, Equatable {
        let id: String
        let startsAt: Date
        let live: Bool
    }
    let id: String
    let subject: String
    let level: String?
    let teacher: String?
    let lesson: Lesson?
}

/// A saved Lugichat conversation the picture can be added to.
struct ShareChat: Identifiable, Decodable, Equatable {
    let id: String
    let title: String
    let lastAt: Date
    let snippet: String
    let hasImage: Bool
}

/// Where the picture goes.
enum ShareChoice: Hashable {
    case newChat
    case chat(String)
    case group(String)
}

/// Talks to /api/native/share/student/* with the scoped share token (the extension never holds the Supabase session).
enum ShareAPI {
    struct Failure: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message.isEmpty ? "שגיאת שרת" : message }
    }

    static var baseURL: URL {
        let host = (Bundle.main.object(forInfoDictionaryKey: "LugipodBaseURL") as? String) ?? ""
        let clean = (host.isEmpty || host.hasPrefix("$(")) ? "lugipod.com" : host
        return URL(string: clean.hasPrefix("http") ? clean : "https://\(clean)")!
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = plain.date(from: s) ?? frac.date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return d
    }()

    static func call(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        guard let token = ShareBridge.token else { throw Failure(status: 401, message: "") }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw Failure(status: 0, message: "תקלה פנימית") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 60
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String ?? ""
        throw Failure(status: status, message: status == 401 ? "" : message)
    }
}

/// Reads the shared picture out of the system's temporary file (which disappears when the callback returns) and shrinks it: longest side
/// 1600 px, JPEG. Small enough for the share request and for the extension's memory limit, sharp enough to read handwriting.
enum ShareImage {
    static func prepare(_ url: URL, maxSide: CGFloat = 1600) -> (image: UIImage, jpeg: Data)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return nil }
        return (image, jpeg)
    }
}

/// The state of one share: load the places, let the student pick, send.
@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case loading, ready, sending, done
        case needsSignIn
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var groups: [ShareGroup] = []
    @Published private(set) var chats: [ShareChat] = []
    @Published var choice: ShareChoice = .newChat
    @Published var note = ""
    /// What was chosen when the picture was sent (for the thank-you text).
    @Published private(set) var sentTo: ShareChoice?
    let image: UIImage
    private let jpeg: Data

    init(image: UIImage, jpeg: Data) {
        self.image = image
        self.jpeg = jpeg
    }

    func load() async {
        phase = .loading
        guard ShareBridge.token != nil else { phase = .needsSignIn; return }
        struct Reply: Decodable { let groups: [ShareGroup]; let chats: [ShareChat] }
        do {
            let reply = try ShareAPI.decoder.decode(Reply.self, from: try await ShareAPI.call("GET", "/api/native/share/student/targets"))
            groups = reply.groups
            chats = reply.chats
            // Most pictures are a question for Lugifox: a new conversation is one tap away, the newest conversation one more.
            choice = .newChat
            phase = .ready
        } catch let f as ShareAPI.Failure where f.status == 401 {
            phase = .needsSignIn
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "לא הצלחנו לטעון. נסו שוב.")
        }
    }

    func send() async {
        guard phase == .ready || isFailed else { return }
        phase = .sending
        var body: [String: Any] = ["imageBase64": jpeg.base64EncodedString(), "mimeType": "image/jpeg", "text": note.trimmingCharacters(in: .whitespacesAndNewlines)]
        switch choice {
        case .newChat: body["kind"] = "lugichat"; body["chatId"] = "new"
        case .chat(let id): body["kind"] = "lugichat"; body["chatId"] = id
        case .group(let id):
            body["kind"] = "prelesson"; body["groupId"] = id
            if let lesson = groups.first(where: { $0.id == id })?.lesson { body["lessonId"] = lesson.id }
        }
        do {
            struct Reply: Decodable { let chatId: String? }
            let reply = try ShareAPI.decoder.decode(Reply.self, from: try await ShareAPI.call("POST", "/api/native/share/student/send", json: body))
            if let chatId = reply.chatId { ShareBridge.setOpenRequest(kind: "lugichat", id: chatId) }
            sentTo = choice
            phase = .done
        } catch let f as ShareAPI.Failure where f.status == 401 {
            phase = .needsSignIn
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "השליחה נכשלה, נסו שוב")
        }
    }

    func retry() { phase = .ready }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
}
