import Foundation

struct WebTarget: Identifiable, Equatable {
    let id = UUID()
    let path: String
}

/// Where the app is: which tab, whether the bell is open, and which website page is open full screen.
/// Push taps and alert rows both go through `open(path:)` with the paths the server puts on each alert.
@MainActor
final class AppRouter: ObservableObject {
    enum Tab: Hashable { case home, lugichat, practice, friends, more }

    @Published var tab: Tab = .home
    @Published var web: WebTarget?
    @Published var showAlerts = false
    /// The welcome tour (first launch, and "סיור היכרות" in עוד).
    @Published var showTour = false
    /// Asks the home to open the "link a parent" sheet (the reminder alert and its push point here).
    @Published var showParentLink = false

    init() {
        #if DEBUG
        if let preview = PreviewMode.tab() { tab = preview }
        showAlerts = PreviewMode.opensAlerts
        // Store screenshots (see AuthStore.autologin): which tab to open, and the bell.
        let env = ProcessInfo.processInfo.environment
        switch env["LUGIPOD_TAB"] {
        case "lugichat": tab = .lugichat
        case "practice": tab = .practice
        case "friends": tab = .friends
        case "more": tab = .more
        default: break
        }
        if env["LUGIPOD_ALERTS"] == "1" { showAlerts = true }
        if env["LUGIPOD_TOUR"] == "1" { showTour = true }
        #endif
    }

    func open(path: String) {
        switch Self.destination(for: path) {
        case .tab(let t): showAlerts = false; tab = t
        case .alerts: showAlerts = true
        case .linkParent:
            let wasOpen = showAlerts
            showAlerts = false
            tab = .home
            Task {
                if wasOpen { try? await Task.sleep(nanoseconds: 450_000_000) }
                showParentLink = true
            }
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

    enum Destination: Equatable { case tab(Tab), alerts, linkParent, web(String) }

    /// `/home`, `/alerts`, `/lugichat` (native), and website paths (the lesson room, the dashboard, ...).
    static func destination(for path: String) -> Destination {
        if path == "/home" || path == "/" { return .tab(.home) }
        if path == "/alerts" { return .alerts }
        if path == "/link-parent" { return .linkParent }
        if path.hasPrefix("/lugichat") { return .tab(.lugichat) }
        if path.hasPrefix("/") && !path.hasPrefix("//") { return .web(path) }
        return .tab(.home)
    }
}
