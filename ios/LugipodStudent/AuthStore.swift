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

    private func bootstrap() async {
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
