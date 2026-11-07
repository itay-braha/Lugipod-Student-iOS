import Foundation

/// A development aid: `LUGIPOD_PREVIEW=<screen>` (an environment variable, set by CI through `simctl launch`) makes a DEBUG build
/// skip sign-in and show a screen with sample data, so every screen can be screenshotted in the simulator without a server.
/// Screens: login, login-code, login-email, home, home-done, lugichat, lugichat-thread, lugichat-limit, more, alerts.
/// Release builds (TestFlight) compile this away: `isOn` is always false there.
enum PreviewMode {
    #if DEBUG
    static let screen: String? = ProcessInfo.processInfo.environment["LUGIPOD_PREVIEW"]
    static var isOn: Bool { screen != nil }
    static var loggedOut: Bool { screen?.hasPrefix("login") == true }

    static func tab() -> AppRouter.Tab? {
        switch screen {
        case "home", "home-done", "alerts": return .home
        case "lugichat", "lugichat-thread", "lugichat-limit": return .lugichat
        case "more": return .more
        default: return nil
        }
    }

    static var opensAlerts: Bool { screen == "alerts" }

    /// A conversation about a photographed question, with formulas.
    static func lugichat() -> (messages: [ChatMessage], limit: Bool)? {
        switch screen {
        case "lugichat-thread", "lugichat-limit":
            return ([
                ChatMessage(role: .bot, body: "בואו נפרק את זה. הגוף נע בתאוצה קבועה, אז נשתמש במשוואות התנועה.\n\n**שלב 1.** מה הנתונים? $v_0 = 0$, $a = 2\\ \\text{m/s}^2$, $t = 5\\ \\text{s}$.\n\n$$x = v_0 t + \\frac{1}{2} a t^2$$\n\nמה יוצא לכם אם מציבים?"),
                ChatMessage(role: .student, body: "25 מטר?"),
                ChatMessage(role: .bot, body: "בדיוק! $x = \\frac{1}{2}\\cdot 2 \\cdot 5^2 = 25\\ \\text{m}$. עכשיו, איך תמצאו את המהירות בסוף התנועה?"),
            ], screen == "lugichat-limit")
        default:
            return nil
        }
    }

    // MARK: Sample server responses

    static func response(method: String, path: String) -> Data {
        if method != "GET" { return Data("{\"ok\":true}".utf8) }
        let json: String
        if path.hasPrefix("/api/native/student/home") { json = home(done: screen == "home-done") }
        else if path.hasPrefix("/api/native/alerts") { json = alerts() }
        else { json = "{}" }
        return Data(json.utf8)
    }

    private static func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    private static func home(done: Bool) -> String {
        """
        {"student":{"id":"s1","name":"נועה כהן","grade":"י׳"},
         "lessons":[
           {"id":"l1","groupId":"g1","title":"מתמטיקה · 5 יח״ל","teacher":"איתי","scheduledAt":"\(iso(-300))","durationMin":90,"phase":"live"},
           {"id":"l2","groupId":"g1","title":"מתמטיקה · 5 יח״ל","teacher":"איתי","scheduledAt":"\(iso(3 * 86400))","durationMin":90,"phase":"upcoming"},
           {"id":"l3","groupId":"g2","title":"פיזיקה · 5 יח״ל","teacher":"רועי","scheduledAt":"\(iso(4 * 86400))","durationMin":90,"phase":"upcoming"}],
         "groups":[
           {"id":"g1","title":"מתמטיקה · 5 יח״ל","teacher":"איתי","members":4,"weekly":1},
           {"id":"g2","title":"פיזיקה · 5 יח״ל","teacher":"רועי","members":3,"weekly":2}],
         "dailyChallenge":{"doneToday":\(done),"streak":6},
         "lugichat":{"free_left":14,"free_per_day":20,"pack_left":0,"can_ask":true},
         "subjects":[{"id":"sub1","name":"מתמטיקה","mine":true},{"id":"sub2","name":"פיזיקה","mine":true},{"id":"sub3","name":"מדעי המחשב","mine":false}],
         "unreadAlerts":2}
        """
    }

    private static func alerts() -> String {
        """
        {"alerts":[
          {"id":"a1","type":"lesson_reminder","title":"השיעור מתחיל בעוד 15 דקות","body":"מתמטיקה · 5 יח״ל עם איתי.","emoji":"⏰","ref_id":"l1","created_at":"\(iso(-600))","read_at":null,"path":"/meeting/lesson/l1"},
          {"id":"a2","type":"streak","title":"אל תשברו את הרצף","body":"האתגר היומי מחכה לכם.","emoji":"🔥","ref_id":null,"created_at":"\(iso(-7200))","read_at":null,"path":"/dashboard"},
          {"id":"a3","type":"lesson_summary","title":"סיכום השיעור מוכן","body":null,"emoji":"📝","ref_id":null,"created_at":"\(iso(-86400))","read_at":"\(iso(-80000))","path":"/dashboard"}],
         "unread":2}
        """
    }
    #else
    static var isOn: Bool { false }
    #endif
}
