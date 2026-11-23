import Foundation
import Supabase
import UIKit

/// The student login. The Supabase SDK refreshes the session; SessionVault keeps it on the device;
/// everything else asks this object for a token.
@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    enum State: Equatable { case loading, notConfigured, signedOut, signedIn }

    @Published private(set) var state: State = .loading
    /// Shown on the login screen after an automatic sign-out (for example, not a student account).
    @Published var notice: String?
    /// Watchers of the session's token (the in-app web pages re-sync their cookie after every refresh).
    @Published private(set) var tokenGeneration = 0

    let client: SupabaseClient
    private let vault = SessionVault.shared
    private let storageKey: String

    private init() {
        let key = SessionVault.storageKey(for: AppConfig.supabaseURL)
        storageKey = key
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseKey,
            options: SupabaseClientOptions(auth: .init(storage: SessionVault.shared, storageKey: key))
        )
        #if DEBUG
        if PreviewMode.isOn {
            state = PreviewMode.loggedOut ? .signedOut : .signedIn
            return
        }
        #endif
        guard AppConfig.isConfigured else {
            state = .notConfigured
            return
        }
        vault.onRepair = { detail in Task { await AuthTelemetry.report("vault_repair", detail) } }
        observeLifecycle()
        Task { await bootstrap() }
    }

    #if DEBUG
    private var debugToken: String?
    private var debugRefresh: String?
    /// Store screenshots only (a DEBUG build; compiled out of Release and TestFlight builds): the simulator launches the app with
    /// LUGIPOD_AUTOLOGIN_EMAIL / LUGIPOD_AUTOLOGIN_PASSWORD and it signs in by itself, so no password is ever typed through the UI.
    nonisolated static var autologin: (email: String, password: String)? {
        let env = ProcessInfo.processInfo.environment
        guard let e = env["LUGIPOD_AUTOLOGIN_EMAIL"], let p = env["LUGIPOD_AUTOLOGIN_PASSWORD"], !e.isEmpty, !p.isEmpty else { return nil }
        return (e, p)
    }
    #endif

    // MARK: Staying signed in
    //
    // Every new login costs a paid WhatsApp code, so the app is signed out ONLY when the login is really gone:
    //   - the person pressed "התנתקות" (signOut), or the account is not a student, or
    //   - Supabase rejected the session and the SDK deleted it (then the vault says `.absent`).
    // A Keychain that can't be read right now, no network, a timeout or a 401 from our API never sign anyone out. Whatever the
    // reason, when the login screen appears its reason is remembered and sent with the next code request, so we can see it.

    private func bootstrap() async {
        #if DEBUG
        if let login = Self.autologin {
            do {
                let session = try await client.auth.signIn(email: login.email, password: login.password)
                DebugLog.write("autologin: signed in")
                do { _ = try await client.auth.session; DebugLog.write("session readable after sign-in") }
                catch { DebugLog.write("session NOT readable after sign-in: \(error)") }
                // The CI simulator's keychain may not keep the session: for screenshots keep the token in memory and go straight in.
                debugToken = session.accessToken
                debugRefresh = session.refreshToken
                state = .signedIn
                return
            } catch { DebugLog.write("autologin FAILED: \(error)") }
        } else { DebugLog.write("autologin: no credentials in the environment") }
        DebugLog.write("configured=\(AppConfig.isConfigured)")
        #endif
        settle(reason: "launch")
        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .tokenRefreshed, .userUpdated:
                if change.session != nil { state = .signedIn }
                if change.event == .tokenRefreshed { tokenGeneration += 1 }
            case .signedOut:
                // Trust the stored session, not the event: the SDK deletes it before it says signed out for real.
                if vault.presence(storageKey) == .absent { moveToSignedOut(reason: explicitSignOut ? "explicit" : "sdk_signed_out") }
            default: break
            }
        }
    }

    /// Decides signed in / signed out from what is stored. While the Keychain can't be read (the device has not been unlocked since
    /// it restarted, e.g. an app pre-launched by iOS) it waits instead of showing the login screen.
    private func settle(reason: String) {
        switch vault.presence(storageKey) {
        case .present:
            state = .signedIn
            unreadableChecks = 0
        case .absent: moveToSignedOut(reason: reason == "launch" ? "no_session_at_launch" : "no_session_\(reason)")
        case .unreadable:
            if state != .signedIn { state = .loading }
            unreadableChecks = reason == "retry" ? unreadableChecks + 1 : 0
            // Waiting is for a device that is still locked. Unlocked and still unreadable after ~30 s: show the login screen rather
            // than a loading screen forever (the next becoming-active check still brings the login back if it turns up).
            if unreadableChecks >= 15 && UIApplication.shared.isProtectedDataAvailable {
                moveToSignedOut(reason: "unreadable_timeout")
                return
            }
            if reason != "retry" { Task { await AuthTelemetry.report("session_unreadable", reason) } }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if state == .loading { vault.forgetCache(); settle(reason: "retry") }
            }
        }
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        for name in [UIApplication.protectedDataDidBecomeAvailableNotification, UIApplication.didBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recheck() }
            }
        }
    }

    /// Back in the app (or the device was unlocked): a login screen shown by mistake goes away by itself if the session is there.
    private func recheck() {
        guard state != .signedIn, state != .notConfigured, !explicitSignOut else { return }
        vault.forgetCache()
        if vault.presence(storageKey) == .present {
            Task { await AuthTelemetry.report("recovered_on_active", lastSignOutReason) }
            state = .signedIn
        } else if state == .loading {
            settle(reason: "recheck")
        }
    }

    /// A screen found no usable session (APIError.notSignedIn). Signs out only if nothing is stored; otherwise it was temporary.
    func sessionLost(_ screen: String) async {
        #if DEBUG
        if debugToken != nil { return }
        #endif
        switch vault.presence(storageKey) {
        case .absent: moveToSignedOut(reason: "session_absent:\(screen)")
        case .present, .unreadable: await AuthTelemetry.report("loss_ignored", screen)
        }
    }

    private var explicitSignOut = false
    private var unreadableChecks = 0
    private var lastSignOutReason: String {
        get { UserDefaults.standard.string(forKey: "lugipod.lastSignOutReason") ?? "unknown" }
        set { UserDefaults.standard.set(newValue, forKey: "lugipod.lastSignOutReason") }
    }

    private func moveToSignedOut(reason: String) {
        let wasIn = state == .signedIn
        lastSignOutReason = reason
        state = .signedOut
        if wasIn && reason != "explicit" { Task { await AuthTelemetry.report("auto_signed_out", reason) } }
    }

    // MARK: Sign in

    /// Step 1: the WhatsApp code, through the site's own throttle (so the app cannot bypass it). If a login is in fact stored, no code is
    /// sent: the app simply goes in.
    func requestCode(phone: String) async throws {
        vault.forgetCache()
        if vault.presence(storageKey) == .present {
            await AuthTelemetry.report("code_skipped_session_present", lastSignOutReason)
            state = .signedIn
            return
        }
        await AuthTelemetry.report("code_requested", lastSignOutReason)
        struct Reply: Decodable { let ok: Bool; let error: String? }
        do {
            let data = try await API.request("POST", "/api/native/otp-request", json: ["phone": phone], authorized: false)
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            if !reply.ok { throw APIError.server(400, reply.error ?? "") }
        } catch APIError.server(let status, let message) where status == 429 || status == 400 {
            throw APIError.server(status, message.isEmpty ? "לא הצלחנו לשלוח קוד. נסו שוב בעוד רגע." : message)
        }
    }

    /// Step 2: Supabase checks the code and signs the device in.
    func verify(phone: String, code: String) async throws {
        notice = nil
        _ = try await client.auth.verifyOTP(phone: Phone.e164(phone), token: code, type: .sms)
        explicitSignOut = false
        state = .signedIn            // do not wait for the SDK's event: the person is in the moment the code was accepted
    }

    /// True when this device already holds a session (the server accepted the code even though the call reported a problem).
    func adoptExistingSession() async -> Bool {
        guard (try? await client.auth.session) != nil else { return false }
        explicitSignOut = false
        state = .signedIn
        return true
    }

    /// What to tell the person when the code did not work: a wrong/used code, no connection, or something else, never one message for all.
    nonisolated static func otpMessage(for error: Error) -> String {
        let t = String(describing: error).lowercased()
        if t.contains("otp_expired") || t.contains("expired or is invalid") || t.contains("invalid") {
            return "הקוד לא התקבל. הקלידו את הקוד האחרון שנשלח אליכם בוואטסאפ, או בקשו חדש בעוד רגע."
        }
        if error is URLError || t.contains("offline") || t.contains("timed out") || t.contains("network") {
            return "אין חיבור לאינטרנט כרגע. בדקו את החיבור ונסו שוב. הקוד עדיין תקף."
        }
        return "משהו השתבש בכניסה. נסו שוב בעוד רגע."
    }

    enum EmailLoginError: Error { case notAllowed }

    /// Email accounts that may use the password door (App Review and our own testing). Everyone else signs in with the phone and the WhatsApp code.
    nonisolated static func emailLoginAllowed(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespaces).lowercased().hasSuffix("@lugipod.demo")
    }

    func signIn(email: String, password: String) async throws {
        guard Self.emailLoginAllowed(email) else { throw EmailLoginError.notAllowed }
        notice = nil
        _ = try await client.auth.signIn(email: email, password: password)
        explicitSignOut = false
        state = .signedIn
    }

    /// The person pressed "התנתקות" (or the account is not a student). Ends THIS device's login only: the website and other devices
    /// stay signed in (the SDK's default would end every session of the person, the phone app included).
    func signOut(notice: String? = nil, reason: String = "explicit") async {
        DebugLog.write("signOut called, notice=\(notice ?? "none")")
        explicitSignOut = true
        await ShareSync.revokeAndClear()
        await PushNotifications.shared.willSignOut()
        try? await client.auth.signOut(scope: .local)
        try? vault.remove(key: storageKey)
        LocalCache.clearAll()
        moveToSignedOut(reason: reason)
        self.notice = notice
    }

    // MARK: Tokens

    /// What a failed session read means: notSignedIn only when no session is stored any more; otherwise a temporary problem.
    private func sessionError(_ error: Error) -> Error {
        vault.presence(storageKey) == .absent ? APIError.notSignedIn : APIError.server(0, "offline")
    }

    /// After a 401 from our API: refresh the session once so the call can be retried. Throws notSignedIn only when the
    /// session is really gone, otherwise a temporary error (the stored session stays).
    func refreshAfterUnauthorized() async throws {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        do { _ = try await client.auth.refreshSession() } catch { throw sessionError(error) }
    }

    func accessToken() async throws -> String {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        #if DEBUG
        if let t = debugToken { return t }
        #endif
        do { return try await client.auth.session.accessToken } catch { throw sessionError(error) }
    }

    /// For signing the in-app web pages in (POST /api/native/web-login).
    func sessionTokens() async throws -> (access: String, refresh: String) {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        #if DEBUG
        if let t = debugToken, let r = debugRefresh { return (t, r) }
        #endif
        do {
            let s = try await client.auth.session
            return (s.accessToken, s.refreshToken)
        } catch { throw sessionError(error) }
    }
}

/// Reports what happens to the login to /api/native/auth-event (table native_auth_events), so a sign-out is never a mystery again.
/// Works signed out; adds the Bearer token when there is one. Never throws, never blocks the UI for long.
enum AuthTelemetry {
    static let app = "student"

    static var installID: String {
        let key = "lugipod.installID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static func report(_ event: String, _ detail: String? = nil) async {
        #if DEBUG
        return   // debug builds (CI, simulator, previews) never report: only real installs
        #endif
        guard AppConfig.isConfigured else { return }
        var req = URLRequest(url: API.baseURL.appendingPathComponent("api/native/auth-event"))
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await MainActor.run(body: { AuthStore.shared.client.auth.currentSession?.accessToken }) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "app": app, "event": event, "detail": detail ?? "", "install": installID,
            "build": (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}
