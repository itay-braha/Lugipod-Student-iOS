import SafariServices
import SwiftUI
import WebKit

/// A handle on a page inside the app, so native buttons can drive it (the lesson's files / report / leave are native buttons on the
/// video since build 133, and the page does the work). Commands arrive in the page as a `lugipod-native` event with `detail.command`.
@MainActor
final class WebController: ObservableObject {
    fileprivate weak var web: WKWebView?

    func send(command: String) {
        let js = "window.dispatchEvent(new CustomEvent(\"lugipod-native\",{detail:{command:\"\(command)\"}}))"
        web?.evaluateJavaScript(js, completionHandler: nil)
    }
}

/// A Lugipod website page inside the app, for the screens that are not native yet (the level test, billing, the lesson page's
/// controls...). The user agent says "LugipodStudentApp/<n>" so the site can tell it is in the app (and which bridge features this
/// build has: 2 = session state + native commands); the lesson page then does NOT join the video call itself, because the app's native
/// client does.
struct WebShell: UIViewRepresentable {
    let request: URLRequest
    /// Messages from the page (`webkit.messageHandlers.lugipod`). Only the lesson screen listens.
    var onMessage: ((BridgeMessage) -> Void)?
    var controller: WebController?
    /// When the sign-in + page load started (for Perf), and which page it is.
    var startedAt: Date = Date()
    var path: String = ""

    func makeCoordinator() -> Coordinator { Coordinator(onMessage: onMessage) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "LugipodStudentApp/2"
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakHandler(context.coordinator), name: "lugipod")
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.uiDelegate = context.coordinator
        web.navigationDelegate = context.coordinator
        web.isInspectable = true
        context.coordinator.startedAt = startedAt
        context.coordinator.path = path
        controller?.web = web
        web.load(request)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        controller?.web = web
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        var onMessage: ((BridgeMessage) -> Void)?
        var startedAt = Date()
        var path = ""
        private var timed = false
        init(onMessage: ((BridgeMessage) -> Void)?) { self.onMessage = onMessage }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let msg = BridgeMessage(body: message.body) else { return }
            DispatchQueue.main.async { self.onMessage?(msg) }
        }

        // Perf: from opening the screen (the sign-in included) until the page first finished loading.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !timed, !path.isEmpty else { return }
            timed = true
            Perf.record(kind: "web", path: path, status: 200, since: startedAt)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { recordFailure() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { recordFailure() }
        private func recordFailure() {
            guard !timed, !path.isEmpty else { return }
            timed = true
            Perf.record(kind: "web", path: path, status: 0, since: startedAt)
        }

        // Camera/microphone prompts for pages inside the app: the site is ours, say yes.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        // target="_blank" links (a lesson file, the picture of a question) open in a viewer ON TOP of the page, with "Done" to come
        // back. Loading them into this same view replaced the lesson page (time, files, leave) and there was no way back to it.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else { return nil }
            if ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let top = Self.topController(from: webView) {
                let viewer = SFSafariViewController(url: url)
                viewer.dismissButtonStyle = .done
                viewer.preferredControlTintColor = UIColor(red: 0.31, green: 0.27, blue: 0.9, alpha: 1)
                viewer.modalPresentationStyle = .pageSheet
                top.present(viewer, animated: true)
            } else {
                webView.load(navigationAction.request)
            }
            return nil
        }

        /// The view controller to present over: the one showing this web view, or whatever is already presented on top of it.
        private static func topController(from view: UIView) -> UIViewController? {
            var top = view.window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
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
    var controller: WebController?
    @Environment(\.dismiss) private var dismiss
    @State private var request: URLRequest?
    @State private var failed = false
    @State private var startedAt = Date()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground).ignoresSafeArea()
            if let request {
                WebShell(request: request, onMessage: onMessage, controller: controller, startedAt: startedAt, path: path)
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
        startedAt = Date()
        do { request = try await WebLogin.request(next: path) } catch { failed = true }
    }
}
