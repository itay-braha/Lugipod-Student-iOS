import Foundation

struct WebTarget: Identifiable, Equatable {
    let id = UUID()
    let path: String
}

/// Where the app is: which tab, whether the bell is open, and which website page is open full screen.
/// Push taps and alert rows both go through `open(path:)` with the paths the server puts on each alert.
@MainActor
final class AppRouter: ObservableObject {
    enum Tab: Hashable { case home, lugichat, practice, more }

    @Published var tab: Tab = .home
    @Published var web: WebTarget?
    @Published var showAlerts = false

    init() {
        #if DEBUG
        if let preview = PreviewMode.tab() { tab = preview }
        showAlerts = PreviewMode.opensAlerts
        #endif
    }

    func open(path: String) {
        switch Self.destination(for: path) {
        case .tab(let t): showAlerts = false; tab = t
        case .alerts: showAlerts = true
        case .web(let p):
            // A sheet and a full-screen cover cannot be presented together: close the bell first.
            if showAlerts {
                showAlerts = false
                Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    web = WebTarget(path: p)
                }
            } else {
                web = WebTarget(path: p)
            }
        }
    }

    enum Destination: Equatable { case tab(Tab), alerts, web(String) }

    /// `/home`, `/alerts`, `/lugichat` (native), and website paths (the lesson room, the dashboard, ...).
    static func destination(for path: String) -> Destination {
        if path == "/home" || path == "/" { return .tab(.home) }
        if path == "/alerts" { return .alerts }
        if path.hasPrefix("/lugichat") { return .tab(.lugichat) }
        if path.hasPrefix("/") && !path.hasPrefix("//") { return .web(path) }
        return .tab(.home)
    }
}
