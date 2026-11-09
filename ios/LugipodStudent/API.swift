import Foundation

enum APIError: LocalizedError {
    case badURL, notSignedIn, notAStudent
    case server(Int, String)

    /// Shown on the login screen when a parent (or anyone who is not a student) signs in. Plain information only: the app is for students, and
    /// family accounts live on the website. No prices, no plans, no payment words, no tappable link (App Store 3.1.3(f)).
    static let notAStudentNotice = "האפליקציה הזו מיועדת לתלמידים. חשבונות של הורים מנוהלים באתר lugipod.com. (למורים יש אפליקציה נפרדת.)"

    var errorDescription: String? {
        switch self {
        case .badURL: return "תקלה פנימית"
        case .notSignedIn: return "יש להתחבר מחדש"
        case .notAStudent: return APIError.notAStudentNotice
        case .server(_, let m): return m.isEmpty ? "שגיאת שרת" : m
        }
    }
}

/// Calls the Lugipod backend as the signed-in student: `Authorization: Bearer <Supabase access token>`
/// (the SDK refreshes the token), so the app never handles passwords or cookies.
enum API {
    static var baseURL: URL {
        let host = (Bundle.main.object(forInfoDictionaryKey: "LugipodBaseURL") as? String) ?? "lugipod.com"
        return URL(string: host.hasPrefix("http") ? host : "https://\(host)")!
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = parseDate(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return d
    }()

    /// Postgres timestamps come as `2026-11-04T09:19:00+00:00`, sometimes with fractional seconds.
    static func parseDate(_ s: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s)
    }

    static func request(_ method: String, _ path: String, json: [String: Any]? = nil, authorized: Bool = true, timeout: TimeInterval = 20) async throws -> Data {
        #if DEBUG
        if PreviewMode.isOn { return PreviewMode.response(method: method, path: path) }
        #endif
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        if authorized {
            let token = try await AuthStore.shared.accessToken()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = obj?["error"] as? String ?? ""
        if status == 401 { throw APIError.notSignedIn }
        if status == 403, message == "not_a_student" { throw APIError.notAStudent }
        throw APIError.server(status, message)
    }

    /// A POST whose answer arrives as server-sent events (`data: {json}` lines separated by a blank line). Each event is handed to
    /// `onEvent` as soon as it is complete, so Lugichat can show the tutor's words while they are written. Errors before the first
    /// event (not signed in, daily limit) come back as a normal status + JSON body, exactly like `request`.
    @MainActor static func stream(_ path: String, json: [String: Any], timeout: TimeInterval = 75, onEvent: ([String: Any]) -> Void) async throws {
        #if DEBUG
        if PreviewMode.isOn {
            var obj = (try? JSONSerialization.jsonObject(with: PreviewMode.response(method: "POST", path: path))) as? [String: Any] ?? [:]
            obj["t"] = "done"
            onEvent(obj)
            return
        }
        #endif
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let token = try await AuthStore.shared.accessToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let isStream = ((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/event-stream")
        if !(200..<300).contains(status) || !isStream {
            var data = Data()
            for try await b in bytes { data.append(b) }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = obj?["error"] as? String ?? ""
            if (200..<300).contains(status), let obj { onEvent(obj.merging(["t": "done"]) { a, _ in a }); return }
            if status == 401 { throw APIError.notSignedIn }
            throw APIError.server(status, message)
        }
        // Events are separated by a blank line; lines are decoded as UTF-8 only once complete (Hebrew is multi-byte).
        var buffer = Data()
        for try await b in bytes {
            buffer.append(b)
            while let end = buffer.range(of: Data([0x0A, 0x0A])) {
                let chunk = buffer.subdata(in: buffer.startIndex..<end.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                guard var line = String(data: chunk, encoding: .utf8) else { continue }
                if line.hasPrefix("data: ") { line.removeFirst(6) }
                if let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] { onEvent(obj) }
            }
        }
    }

    static func post(_ path: String, json: [String: Any]) async throws -> Data {
        try await request("POST", path, json: json)
    }

    static func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try decoder.decode(T.self, from: try await request("GET", path))
    }
}
