import SwiftUI
import WebKit

/// A Lugipod website page inside the app, for the screens that are not native yet (availability, the level test, billing, the lesson
/// page's controls...). The user agent says "LugipodStudentApp" so the site can tell it is in the app; the lesson page then does NOT join
/// the video call itself, because the app's native client does.
struct WebShell: UIViewRepresentable {
    let request: URLRequest
    /// Messages from the page (`webkit.messageHandlers.lugipod`). Only the lesson screen listens.
    var onMessage: ((BridgeMessage) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onMessage: onMessage) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "LugipodStudentApp/1"
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakHandler(context.coordinator), name: "lugipod")
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.uiDelegate = context.coordinator
        web.isInspectable = true
        web.load(request)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) { context.coordinator.onMessage = onMessage }

    final class Coordinator: NSObject, WKUIDelegate, WKScriptMessageHandler {
        var onMessage: ((BridgeMessage) -> Void)?
        init(onMessage: ((BridgeMessage) -> Void)?) { self.onMessage = onMessage }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let msg = BridgeMessage(body: message.body) else { return }
            DispatchQueue.main.async { self.onMessage?(msg) }
        }

        // Camera/microphone prompts for pages inside the app: the site is ours, say yes.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        // target="_blank" links open in the same view instead of nowhere.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }

    /// WKUserContentController retains its handlers; this breaks the cycle.
    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(ucc, didReceive: message)
        }
    }
}

/// Builds the request that signs the web view in with the native session, then lands on `path`.
enum WebLogin {
    static func request(next path: String) async throws -> URLRequest {
        let tokens = try await AuthStore.shared.sessionTokens()
        var req = URLRequest(url: API.baseURL.appendingPathComponent("api/native/web-login"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody(["access_token": tokens.access, "refresh_token": tokens.refresh, "next": path])
        return req
    }

    static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = fields.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        return pairs.sorted().joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

/// A website page signed in with the native session. Full screen (with a close button) or embedded in a tab.
struct WebScreen: View {
    let path: String
    var showsClose = true
    var onMessage: ((BridgeMessage) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var request: URLRequest?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground).ignoresSafeArea()
            if let request {
                WebShell(request: request, onMessage: onMessage)
            } else if failed {
                ContentUnavailableView {
                    Label("לא הצלחנו לפתוח את העמוד", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("נסו שוב") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showsClose {
                Button { dismiss() } label: {
                    Label("סגירה", systemImage: "xmark")
                        .font(.heebo(14, 800)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.slate200, lineWidth: 1))
                        .shadow(color: Theme.shadowSoft2, radius: 8, y: 3)
                }
                .padding(.horizontal, 12).padding(.top, 4)
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        do { request = try await WebLogin.request(next: path) } catch { failed = true }
    }
}
