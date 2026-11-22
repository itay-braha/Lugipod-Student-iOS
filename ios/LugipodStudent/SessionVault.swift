import Foundation
import Security
import Supabase

/// Where the login lives on this device: the Supabase SDK's session storage, made hard to lose.
///
/// Every new login is a paid WhatsApp code, so a session that still works must never look "gone". The SDK's own Keychain storage
/// turns every read problem into "no session" (a Keychain that is briefly unreadable, an item in another access group, …) and the
/// app then showed the login screen although the login was fine. This storage:
///   - keeps the last value in memory for the whole run (a later read can't lose it);
///   - keeps a second copy in a file (Application Support, protected until the first unlock, never backed up) and restores the
///     Keychain from it if the Keychain item is missing;
///   - tells "absent" (really no login) apart from "unreadable" (try again later), see `presence`;
///   - writes the Keychain update-first, so an item stays in the access group it already lives in (the SDK adds first, which after the
///     share-extension Keychain group was added could leave two copies);
///   - uses the SDK's own Keychain service and key, so existing logins carry over untouched.
final class SessionVault: AuthLocalStorage, @unchecked Sendable {
    enum Presence: Equatable { case present, absent, unreadable }
    enum VaultError: Error { case unreadable(Int32), writeFailed }

    static let shared = SessionVault(primary: KeychainBackend(), backup: FileBackend.standard)

    /// The key the SDK stores the session under: "sb-<project ref>-auth-token" (SupabaseClient's default), passed explicitly.
    static func storageKey(for url: URL) -> String {
        let ref = (url.host ?? "").split(separator: ".").first.map(String.init) ?? ""
        return ref.isEmpty ? "supabase.auth.token" : "sb-\(ref)-auth-token"
    }

    /// Called when the vault had to repair something (restored from the file, read the file because the Keychain could not be read).
    /// Set once at launch; the app reports it to the server.
    var onRepair: (@Sendable (String) -> Void)?

    private let primary: VaultBackend
    private let backup: VaultBackend
    private let lock = NSLock()
    /// key → value (nil = known to be absent). Missing key = not read yet this run.
    private var memory: [String: Data?] = [:]

    init(primary: VaultBackend, backup: VaultBackend) {
        self.primary = primary
        self.backup = backup
    }

    // MARK: AuthLocalStorage

    func store(key: String, value: Data) throws {
        lock.withLock { memory[key] = .some(value) }
        let keychainOK = primary.write(key, value)
        let fileOK = backup.write(key, value)
        if !keychainOK && !fileOK { throw VaultError.writeFailed }   // the memory copy still serves this run
    }

    func retrieve(key: String) throws -> Data? {
        if let cached = lock.withLock({ memory[key] }) { return cached }
        switch primary.read(key) {
        case .found(let data):
            remember(key, data)
            if case .found(let copy) = backup.read(key), copy == data {} else { _ = backup.write(key, data) }
            return data
        case .notFound:
            switch backup.read(key) {
            case .found(let copy):
                _ = primary.write(key, copy)
                remember(key, copy)
                onRepair?("keychain_missing_restored_from_file")
                return copy
            case .notFound:
                remember(key, nil)
                return nil
            case .failed:
                // The Keychain has nothing but the copy cannot be read yet (before the first unlock): not "signed out".
                throw VaultError.unreadable(errSecItemNotFound)
            }
        case .failed(let status):
            if case .found(let copy) = backup.read(key) {
                remember(key, copy)
                onRepair?("keychain_unreadable_\(status)_used_file")
                return copy
            }
            throw VaultError.unreadable(status)
        }
    }

    func remove(key: String) throws {
        lock.withLock { memory[key] = .some(nil) }
        primary.delete(key)
        backup.delete(key)
    }

    // MARK: For AuthStore

    /// Is a login stored? `.unreadable` means "can't tell right now" and must never be treated as signed out.
    func presence(_ key: String) -> Presence {
        do { return try retrieve(key: key) == nil ? .absent : .present } catch { return .unreadable }
    }

    /// Forget what this run read (used before re-checking after the device unlocks).
    func forgetCache() { lock.withLock { memory.removeAll() } }

    private func remember(_ key: String, _ value: Data?) { lock.withLock { memory[key] = .some(value) } }
}

enum VaultRead: Equatable { case found(Data), notFound, failed(Int32) }

protocol VaultBackend: Sendable {
    func read(_ key: String) -> VaultRead
    func write(_ key: String, _ data: Data) -> Bool
    func delete(_ key: String)
}

/// The same Keychain item the Supabase SDK uses (service "supabase.gotrue.swift", account = key, no explicit access group).
struct KeychainBackend: VaultBackend {
    let service = "supabase.gotrue.swift"

    private func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    func read(_ key: String) -> VaultRead {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return .found(data) }
        if status == errSecItemNotFound { return .notFound }
        return .failed(status)
    }

    func write(_ key: String, _ data: Data) -> Bool {
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let updated = SecItemUpdate(base(key) as CFDictionary, attrs as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var add = base(key)
        add.merge(attrs) { _, new in new }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func delete(_ key: String) { SecItemDelete(base(key) as CFDictionary) }
}

/// The second copy: one small file per key in Application Support, encrypted by iOS until the first unlock, excluded from backups.
struct FileBackend: VaultBackend {
    let directory: URL

    static let standard: FileBackend = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return FileBackend(directory: root.appendingPathComponent("LugipodAuth", isDirectory: true))
    }()

    private func url(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".session")
    }

    func read(_ key: String) -> VaultRead {
        let file = url(key)
        guard FileManager.default.fileExists(atPath: file.path) else { return .notFound }
        do { return .found(try Data(contentsOf: file)) } catch { return .failed(-1) }
    }

    func write(_ key: String, _ data: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var file = url(key)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? file.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    func delete(_ key: String) { try? FileManager.default.removeItem(at: url(key)) }
}
