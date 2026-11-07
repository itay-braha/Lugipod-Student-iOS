import Foundation

/// A development aid: `LUGIPOD_PREVIEW=<screen>` (an environment variable, set by CI through `simctl launch`) makes a DEBUG build
/// skip sign-in and show a screen with sample data, so every screen can be screenshotted in the simulator without a server.
/// Screens: availability, home-limit, celebrate, coins, post-lesson, post-lesson-encore, call, login, login-code, login-email, home, home-parent, group, ask, lugichat, lugichat-thread, lugichat-limit, daily, daily-answered, more, alerts.
/// Release builds (TestFlight) compile this away: `isOn` is always false there.
enum PreviewMode {
    #if DEBUG
    static let screen: String? = ProcessInfo.processInfo.environment["LUGIPOD_PREVIEW"]
    static var isOn: Bool { screen != nil }
    static var loggedOut: Bool { screen?.hasPrefix("login") == true }

    static func tab() -> AppRouter.Tab? {
        switch screen {
        case "home", "home-parent", "home-limit", "group", "ask", "alerts": return .home
        case "lugichat", "lugichat-thread", "lugichat-limit": return .lugichat
        case "daily", "daily-answered": return .practice
        case "more", "availability": return .more
        case "celebrate", "coins": return .practice
        default: return nil
        }
    }

    static var opensAlerts: Bool { screen == "alerts" }

    /// A conversation about a photographed question, with formulas.
    static func lugichat() -> (messages: [ChatMessage], limit: Bool)? {
        switch screen {
        case "lugichat-thread", "lugichat-limit":
            return ([
                ChatMessage(role: .student, body: "אני לא מבין איך מוצאים את המהירות אחרי 5 שניות"),
                ChatMessage(role: .bot, body: "בואו נפרק את זה. הגוף יוצא ממנוחה ומאיץ בתאוצה קבועה, אז נשתמש במשוואות התנועה.\n\n**שלב 1.** מה הנתונים? $v_0 = 0$, $a = 2\\ \\text{m/s}^2$, $t = 5\\ \\text{s}$.\n\n$$v = v_0 + a t$$\n\nמה יוצא לכם אם מציבים?"),
                ChatMessage(role: .student, body: "10 מטר לשנייה?"),
                ChatMessage(role: .bot, body: "בדיוק! $v = 0 + 2 \\cdot 5 = 10\\ \\text{m/s}$. עכשיו, איך תמצאו את המרחק שהוא עבר באותן 5 שניות?"),
            ], screen == "lugichat-limit")
        default:
            return nil
        }
    }

    /// An open "same time next week?" offer.
    static func rebook() -> ActiveRebook? {
        let json = """
        {"proposalId":"p1","subjectName":"מתמטיקה","emoji":"📐","myResponse":"pending","isNearMiss":false,"teacherName":"איתי","proposedSlotLabel":null,"originalSlotLabel":null,
         "peers":[{"name":"נועה כהן","response":"pending","isMe":true},{"name":"דנה לוי","response":"yes","isMe":false},{"name":"יואב מזרחי","response":"pending","isMe":false}]}
        """
        return try? API.decoder.decode(ActiveRebook.self, from: Data(json.utf8))
    }

    // MARK: Sample server responses

    static func response(method: String, path: String) -> Data {
        if path.hasPrefix("/api/native/student/daily/answer") { return Data("{\"streak\":7}".utf8) }
        if method != "GET" { return Data("{\"ok\":true}".utf8) }
        let json: String
        if path.hasPrefix("/api/native/student/daily") { json = daily() }
        else if path.hasPrefix("/api/native/student/group/") { json = groupDetail() }
        else if path.hasPrefix("/api/native/student/home") { json = home() }
        else if path.hasPrefix("/api/native/alerts") { json = alerts() }
        else { json = "{}" }
        return Data(json.utf8)
    }

    private static func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    private static func home() -> String {
        let parent = screen == "home-parent" ? "true" : "false"
        let limit = screen == "home-limit"
        return """
        {"student":{"id":"s1","name":"נועה כהן"},
         "groups":[
          {"id":"g1","title":"מתמטיקה · 5 יח״ל","subject":"מתמטיקה","teacher":"איתי","mates":["דנה","יואב","תמר"],"weekly":2,
           "upcoming":[{"id":"l1","groupId":"g1","scheduledAt":"\(iso(-300))","durationMin":90,"extra":false},{"id":"l1b","groupId":"g1","scheduledAt":"\(iso(3 * 86400))","durationMin":90,"extra":false}],
           "last":{"id":"p1","scheduledAt":"\(iso(-3 * 86400))","topics":"פונקציה ריבועית: קודקוד וחיתוכים עם הצירים","homeworkText":"שאלות 3 עד 6 בדף"},
           "homework":[{"id":"h1","title":"פונקציות ריבועיות","status":"assigned","dueDate":"2026-11-10","total":6,"correct":2}],
           "pastCount":7,"myQuestions":1},
          {"id":"g2","title":"פיזיקה · 5 יח״ל","subject":"פיזיקה","teacher":"רועי","mates":["איתן","מאיה"],"weekly":2,
           "upcoming":[{"id":"l2","groupId":"g2","scheduledAt":"\(iso(26 * 3600))","durationMin":90,"extra":false}],
           "last":{"id":"p2","scheduledAt":"\(iso(-2 * 86400))","topics":"תנועה בתאוצה קבועה","homeworkText":null},
           "homework":[{"id":"h2","title":"קינמטיקה","status":"completed","dueDate":null,"total":5,"correct":4}],
           "pastCount":4,"myQuestions":0},
          {"id":"g3","title":"מדעי המחשב · 5 יח״ל","subject":"מדעי המחשב","teacher":"נועה","mates":[],"weekly":1,
           "upcoming":[{"id":"l3","groupId":"g3","scheduledAt":"\(iso(5 * 86400))","durationMin":60,"extra":false}],
           "last":null,"homework":[],"pastCount":0,"myQuestions":0},
          {"id":"g4","title":"כימיה · כיתה י׳","subject":"כימיה","teacher":"דנה","mates":["שיר"],"weekly":1,
           "upcoming":[{"id":"l4","groupId":"g4","scheduledAt":"\(iso(6 * 86400))","durationMin":60,"extra":false}],
           "last":null,"homework":[],"pastCount":0,"myQuestions":0}],
         "badge":{"title":{"emoji":"🚀","label":"חוקר מכניקה","rarity":"rare"},"avatar":"🦊","frame":"frame_violet"},
         "points":{"level":"להבה","balance":340,"lifetime":560,"nextLevelAt":500,"missionsOpen":2},
         "consumption":{"period":"2026-11","consumedLugis":\(limit ? "12" : "7.5"),"capLugis":12,"pctUsed":62,"uncapped":false,"limitReached":\(limit ? "true" : "false")},
         "family":{"hasParent":\(parent)},
         "dailyChallenge":{"doneToday":false,"streak":6},
         "lugichat":{"free_left":14,"free_per_day":20,"pack_left":0,"can_ask":true},
         "unreadAlerts":2}
        """
    }

    private static func groupDetail() -> String {
        """
        {"past":[
          {"id":"p1","scheduledAt":"\(iso(-3 * 86400))","durationMin":90,"topics":"פונקציה ריבועית: קודקוד וחיתוכים עם הצירים","homeworkText":"שאלות 3 עד 6 בדף","attended":true},
          {"id":"p0","scheduledAt":"\(iso(-10 * 86400))","durationMin":90,"topics":"משוואות ריבועיות ונוסחת השורשים","homeworkText":null,"attended":true},
          {"id":"pm1","scheduledAt":"\(iso(-17 * 86400))","durationMin":90,"topics":"מבוא לפרבולה","homeworkText":null,"attended":false}],
         "upcoming":[{"id":"l1","scheduledAt":"\(iso(-300))","durationMin":90,"extra":false},{"id":"l1b","scheduledAt":"\(iso(3 * 86400))","durationMin":90,"extra":false},{"id":"l1c","scheduledAt":"\(iso(7 * 86400))","durationMin":90,"extra":true}],
         "homework":[{"id":"h1","title":"פונקציות ריבועיות","status":"assigned","dueDate":"2026-11-10","total":6,"correct":2,"lessonId":"p1"}],
         "questions":[{"id":"q1","hasImage":true,"lessonId":"l1","text":"אני לא מבין איך מוצאים את הקודקוד כשאין b","createdAt":"\(iso(-7200))"}]}
        """
    }

    private static func daily() -> String {
        """
        {"subject":{"id":"sub1","name":"פיזיקה"},"level":"5 יח״ל","doneToday":false,"streak":6,
         "questions":[{"id":"q1","prompt":"גוף יוצא ממנוחה ומאיץ בתאוצה קבועה של $2\\\\ \\\\text{m/s}^2$. מה מהירותו אחרי $5$ שניות?","choices":["$5\\\\ \\\\text{m/s}$","$10\\\\ \\\\text{m/s}$","$25\\\\ \\\\text{m/s}$","$50\\\\ \\\\text{m/s}$"],"answerIndex":1,"explanation":"המהירות היא $v = v_0 + at = 0 + 2 \\\\cdot 5 = 10\\\\ \\\\text{m/s}$."},
                     {"id":"q2","prompt":"מהו כוח הנורמל על ספר במנוחה על שולחן?","choices":["שווה למשקל הספר","גדול ממשקל הספר","אפס","תלוי בצבע השולחן"],"answerIndex":0,"explanation":"הספר במנוחה, לכן הכוחות עליו מאוזנים והנורמל שווה למשקל."}]}
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
