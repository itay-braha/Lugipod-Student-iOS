import XCTest
@testable import LugipodStudent

/// The login must survive a Keychain that can't be read, a Keychain item that disappeared, and repeated reads; it may only be gone after
/// an explicit remove (sign-out, or the SDK deleting a session Supabase rejected).
final class SessionVaultTests: XCTestCase {
    final class FakeStore: VaultBackend, @unchecked Sendable {
        var items: [String: Data] = [:]
        var failReads: Int32? = nil
        var failWrites = false
        func read(_ key: String) -> VaultRead {
            if let status = failReads { return .failed(status) }
            return items[key].map(VaultRead.found) ?? .notFound
        }
        func write(_ key: String, _ data: Data) -> Bool {
            if failWrites { return false }
            items[key] = data
            return true
        }
        func delete(_ key: String) { items[key] = nil }
    }

    let key = "sb-test-auth-token"
    let session = Data("session".utf8)

    func testStoreWritesBothCopiesAndReadsBack() throws {
        let keychain = FakeStore(), file = FakeStore()
        let vault = SessionVault(primary: keychain, backup: file)
        try vault.store(key: key, value: session)
        XCTAssertEqual(keychain.items[key], session)
        XCTAssertEqual(file.items[key], session)
        XCTAssertEqual(try vault.retrieve(key: key), session)
        XCTAssertEqual(vault.presence(key), .present)
    }

    func testUnreadableKeychainUsesTheFileCopy() throws {
        let keychain = FakeStore(), file = FakeStore()
        file.items[key] = session
        keychain.failReads = errSecInteractionNotAllowed
        let vault = SessionVault(primary: keychain, backup: file)
        final class Box: @unchecked Sendable { var repairs: [String] = [] }
        let box = Box()
        vault.onRepair = { box.repairs.append($0) }
        XCTAssertEqual(try vault.retrieve(key: key), session)
        XCTAssertEqual(box.repairs.count, 1)
    }

    func testUnreadableEverywhereIsNotSignedOut() {
        let keychain = FakeStore(), file = FakeStore()
        keychain.failReads = errSecInteractionNotAllowed
        file.failReads = -1
        let vault = SessionVault(primary: keychain, backup: file)
        XCTAssertEqual(vault.presence(key), .unreadable)       // the app waits, it does not show the login screen
        XCTAssertThrowsError(try vault.retrieve(key: key))
    }

    func testKeychainThatAlwaysFailsWithNoCopyIsNoLogin() {
        let keychain = FakeStore(), file = FakeStore()
        keychain.failReads = -34018                            // e.g. a build without the Keychain entitlement (CI simulator)
        let vault = SessionVault(primary: keychain, backup: file)
        XCTAssertEqual(vault.presence(key), .absent)          // the login screen, not an endless loading screen
    }

    func testMissingKeychainItemIsRestoredFromTheFile() throws {
        let keychain = FakeStore(), file = FakeStore()
        file.items[key] = session
        let vault = SessionVault(primary: keychain, backup: file)
        XCTAssertEqual(try vault.retrieve(key: key), session)
        XCTAssertEqual(keychain.items[key], session)
    }

    func testOldLoginInTheKeychainOnlyCarriesOverAndGetsACopy() throws {
        let keychain = FakeStore(), file = FakeStore()
        keychain.items[key] = session                           // a login stored by the SDK before this storage existed
        let vault = SessionVault(primary: keychain, backup: file)
        XCTAssertEqual(try vault.retrieve(key: key), session)
        XCTAssertEqual(file.items[key], session)
    }

    func testOnceReadALaterKeychainFailureDoesNotLoseIt() throws {
        let keychain = FakeStore(), file = FakeStore()
        keychain.items[key] = session
        let vault = SessionVault(primary: keychain, backup: file)
        _ = try vault.retrieve(key: key)
        keychain.failReads = errSecInteractionNotAllowed
        file.failReads = -1
        XCTAssertEqual(try vault.retrieve(key: key), session)  // the memory copy serves the rest of the run
    }

    func testRemoveIsTheOnlyWayOut() throws {
        let keychain = FakeStore(), file = FakeStore()
        let vault = SessionVault(primary: keychain, backup: file)
        try vault.store(key: key, value: session)
        try vault.remove(key: key)
        XCTAssertNil(keychain.items[key])
        XCTAssertNil(file.items[key])
        XCTAssertEqual(vault.presence(key), .absent)
        vault.forgetCache()
        XCTAssertEqual(vault.presence(key), .absent)
    }

    func testNothingStoredIsAbsent() {
        let vault = SessionVault(primary: FakeStore(), backup: FakeStore())
        XCTAssertEqual(vault.presence(key), .absent)
    }

    func testKeychainWriteFailureStillKeepsTheFileAndMemory() throws {
        let keychain = FakeStore(), file = FakeStore()
        keychain.failWrites = true
        let vault = SessionVault(primary: keychain, backup: file)
        try vault.store(key: key, value: session)
        XCTAssertEqual(file.items[key], session)
        vault.forgetCache()
        XCTAssertEqual(try vault.retrieve(key: key), session)
    }

    func testStorageKeyMatchesTheSDKDefault() {
        XCTAssertEqual(SessionVault.storageKey(for: URL(string: "https://abcdefgh.supabase.co")!), "sb-abcdefgh-auth-token")
    }
}
