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

    static func clearAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix("lugipod-") { try? FileManager.default.removeItem(at: f) }
    }
}
