import Foundation
import Supabase

/// The student login. The Supabase SDK keeps the session in the Keychain and refreshes it;
/// everything else asks this object for a token.
@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    enum State: Equatable { case loading, notConfigured, signedOut, signedIn }

    @Published private(set) var state: State = .loading
    /// Shown on the login screen after an automatic sign-out (for example, not a student account).
    @Published var notice: String?

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
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
        Task { await bootstrap() }
    }

    #if DEBUG
    /// Store screenshots only (a DEBUG build; compiled out of Release and TestFlight builds): the simulator launches the app with
    /// LUGIPOD_AUTOLOGIN_EMAIL / LUGIPOD_AUTOLOGIN_PASSWORD and it signs in by itself, so no password is ever typed through the UI.
    static var autologin: (email: String, password: String)? {
        let env = ProcessInfo.processInfo.environment
        guard let e = env["LUGIPOD_AUTOLOGIN_EMAIL"], let p = env["LUGIPOD_AUTOLOGIN_PASSWORD"], !e.isEmpty, !p.isEmpty else { return nil }
        return (e, p)
    }
    #endif

    private func bootstrap() async {
        #if DEBUG
        if let login = Self.autologin { _ = try? await client.auth.signIn(email: login.email, password: login.password) }
        #endif
        state = (try? await client.auth.session) != nil ? .signedIn : .signedOut
        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .tokenRefreshed: if change.session != nil { state = .signedIn }
            case .signedOut: state = .signedOut
            default: break
            }
        }
    }

    // MARK: Sign in

    /// Step 1: the WhatsApp code, through the site's own throttle (so the app cannot bypass it).
    func requestCode(phone: String) async throws {
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
        state = .signedIn            // do not wait for the SDK's event: the person is in the moment the code was accepted
    }

    /// True when this device already holds a session (the server accepted the code even though the call reported a problem).
    func adoptExistingSession() async -> Bool {
        guard (try? await client.auth.session) != nil else { return false }
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

    func signIn(email: String, password: String) async throws {
        notice = nil
        _ = try await client.auth.signIn(email: email, password: password)
    }

    func signOut(notice: String? = nil) async {
        await PushNotifications.shared.willSignOut()
        try? await client.auth.signOut()
        LocalCache.clearAll()
        state = .signedOut
        self.notice = notice
    }

    // MARK: Tokens

    func accessToken() async throws -> String {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        do { return try await client.auth.session.accessToken } catch { throw APIError.notSignedIn }
    }

    /// For signing the in-app web pages in (POST /api/native/web-login).
    func sessionTokens() async throws -> (access: String, refresh: String) {
        guard AppConfig.isConfigured else { throw APIError.notSignedIn }
        do {
            let s = try await client.auth.session
            return (s.accessToken, s.refreshToken)
        } catch { throw APIError.notSignedIn }
    }
}
