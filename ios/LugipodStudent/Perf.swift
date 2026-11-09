import Foundation
import Network

/// How fast the app really is on this phone (real-user monitoring). Every request is timed here (how long it waited for the login token,
/// how long the whole request took) and every in-app website page until it finished loading. The timings are sent to the server in small
/// batches (POST /api/native/perf → table client_perf, migration 0255), so "it's slow" comes with numbers: which screen, which request,
/// Wi-Fi or cellular, the token refresh or the network. Nothing personal is sent: the path (ids replaced by ":id"), the status, the times.
actor Perf {
    static let shared = Perf()

    struct Item: Encodable {
        let kind: String         // "api" | "web" | "screen"
        let method: String?
        let path: String
        let status: Int
        let totalMs: Int
        let tokenMs: Int?
        let bytes: Int?
        let at: Int64             // epoch ms
    }

    private var items: [Item] = []
    private var flushing = false
    private var lastFlush = Date()
    private let monitor = NWPathMonitor()
    private var network = "other"

    init() {
        monitor.pathUpdateHandler = { path in
            let kind = path.usesInterfaceType(.wifi) ? "wifi" : path.usesInterfaceType(.cellular) ? "cellular" : "other"
            Task { await Perf.shared.setNetwork(kind) }
        }
        monitor.start(queue: DispatchQueue(label: "lugipod.perf.network"))
    }

    private func setNetwork(_ kind: String) { network = kind }

    /// Records one timing. Never throws, never waits for the network.
    nonisolated static func record(kind: String = "api", method: String? = nil, path: String, status: Int, since start: Date, tokenMs: Int? = nil, bytes: Int? = nil) {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        let item = Item(kind: kind, method: method, path: Self.clean(path), status: status, totalMs: Int(Date().timeIntervalSince(start) * 1000),
                        tokenMs: tokenMs, bytes: bytes, at: Int64(start.timeIntervalSince1970 * 1000))
        Task { await shared.add(item) }
    }

    /// `/api/native/student/group/1b2c…?x=1` → `/api/native/student/group/:id` (no ids, no query).
    nonisolated static func clean(_ path: String) -> String {
        let noQuery = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        return noQuery.replacingOccurrences(of: "[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}", with: ":id", options: .regularExpression)
    }

    private func add(_ item: Item) {
        guard item.path != "/api/native/perf" else { return }
        items.append(item)
        if items.count > 400 { items.removeFirst(items.count - 400) }   // offline for long: keep the newest
        if items.count >= 25 || Date().timeIntervalSince(lastFlush) > 45 { Task { await flush() } }
    }

    /// Sends what is collected (also called when the app goes to the background).
    func flush() async {
        guard !flushing, !items.isEmpty, AppConfig.isConfigured else { return }
        flushing = true
        defer { flushing = false }
        let batch = Array(items.prefix(200))
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        struct Body: Encodable { let app: String; let build: String; let network: String; let items: [Item] }
        guard let token = try? await AuthStore.shared.accessToken(),
              let url = URL(string: "/api/native/perf", relativeTo: API.baseURL),
              let body = try? JSONEncoder().encode(Body(app: "student-ios", build: build, network: network, items: batch)) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        lastFlush = Date()
        // Sent with URLSession directly (not API.request), so sending the timings is never itself timed.
        if let (_, resp) = try? await URLSession.shared.data(for: req), ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 300 {
            items.removeFirst(min(batch.count, items.count))
        }
    }
}
