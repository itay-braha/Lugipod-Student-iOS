import Foundation

/// The last server answer for each screen, kept on disk: the app paints from it the moment it opens (no spinner, no empty screen),
/// then the real answer arrives a moment later and replaces it. It holds the raw JSON, so it decodes with exactly the same code.
/// Cleared on sign-out. Lives in Caches (the system may drop it, which only costs one normal load).
enum LocalCache {
    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private static func url(_ name: String) -> URL {
        folder.appendingPathComponent("lugipod-\(name.replacingOccurrences(of: "/", with: "_")).json")
    }

    static func read(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }

    static func write(_ name: String, _ data: Data) { try? data.write(to: url(name), options: .atomic) }

    @MainActor static func clearAll() {
        Prefetch.reset()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix("lugipod-") { try? FileManager.default.removeItem(at: f) }
    }
}

/// The screens behind a tap (my hours, history, friends, profile, saved chats) are fetched in the background once the home is in, and
/// kept with LocalCache under the same names their screens read. Opening any of them then paints at once from that copy while the
/// screen asks for a fresh one. At most every three minutes, all at the same time, never in front of anything the student is waiting for.
@MainActor
enum Prefetch {
    private static var lastRun: Date?

    static let screens: [(path: String, cache: String)] = [
        ("/api/native/student/availability", "availability"),
        ("/api/native/student/history", "history"),
        ("/api/native/student/friends", "friends"),
        ("/api/native/student/profile", "profile"),
        ("/api/native/student/chats", "chats"),
    ]

    static func warm() async {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        if let lastRun, Date().timeIntervalSince(lastRun) < 180 { return }
        lastRun = Date()
        await withTaskGroup(of: Void.self) { group in
            for s in screens {
                group.addTask {
                    if let raw = try? await API.request("GET", s.path) { LocalCache.write(s.cache, raw) }
                }
            }
        }
    }

    /// After sign-out the next account starts fresh.
    static func reset() { lastRun = nil }
}
