import Foundation

// JSON from /api/native/* (keys are snake_case or camelCase; API.decoder handles both).

enum LessonPhase: String, Decodable { case upcoming, live, ended }

/// GET /api/native/student/home: everything the home screen shows, in one response.
struct StudentHome: Decodable, Equatable {
    struct Student: Decodable, Equatable { let id: String; let name: String }

    struct Lesson: Decodable, Identifiable, Equatable {
        let id: String
        let groupId: String
        let scheduledAt: Date
        let durationMin: Int
        let extra: Bool

        /// Computed on the device, so a lesson turns "live" 15 minutes before it starts without waiting for a refresh.
        func phase(now: Date = Date()) -> LessonPhase {
            let end = scheduledAt.addingTimeInterval(Double(durationMin + 15) * 60)
            if now > end { return .ended }
            return now >= scheduledAt.addingTimeInterval(-15 * 60) ? .live : .upcoming
        }
    }

    struct LastLesson: Decodable, Equatable {
        let id: String
        let scheduledAt: Date
        let topics: String?
        let homeworkText: String?
    }

    struct Homework: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        let status: String
        let dueDate: String?
        let total: Int
        let correct: Int
        var isDone: Bool { status == "completed" || status == "done" }
    }

    struct Group: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        let subject: String
        let teacher: String?
        let mates: [String]
        let weekly: Int
        let upcoming: [Lesson]
        let last: LastLesson?
        let homework: [Homework]
        let pastCount: Int
        let myQuestions: Int

        /// The next lesson that has not ended yet (live now, or the closest coming one).
        func nextLesson(now: Date = Date()) -> Lesson? { upcoming.first { $0.phase(now: now) != .ended } }
    }

    struct Consumption: Decodable, Equatable {
        let period: String?
        let consumedLugis: Double
        let capLugis: Double?
        let pctUsed: Double
        let uncapped: Bool
        let creditLugis: Double
    }

    struct Family: Decodable, Equatable { let hasParent: Bool }
    struct Daily: Decodable, Equatable { let doneToday: Bool; let streak: Int }

    let student: Student
    let groups: [Group]
    let consumption: Consumption
    let family: Family
    let dailyChallenge: Daily
    let lugichat: Quota?
    let unreadAlerts: Int
}

/// GET /api/native/student/group/<id>
struct GroupDetail: Decodable, Equatable {
    struct Past: Decodable, Identifiable, Equatable {
        let id: String
        let scheduledAt: Date
        let durationMin: Int
        let topics: String?
        let homeworkText: String?
        let attended: Bool?
    }
    struct Upcoming: Decodable, Identifiable, Equatable {
        let id: String
        let scheduledAt: Date
        let durationMin: Int
        let extra: Bool
    }
    struct Question: Decodable, Identifiable, Equatable {
        let id: String
        let lessonId: String?
        let text: String
        let createdAt: Date
    }
    struct Homework: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        let status: String
        let dueDate: String?
        let total: Int
        let correct: Int
        let lessonId: String?
        var isDone: Bool { status == "completed" || status == "done" }
    }
    let past: [Past]
    let upcoming: [Upcoming]
    let homework: [Homework]
    let questions: [Question]
}

/// The Lugichat allowance. Every field is optional so an older server cannot break the app. The app never shows the daily figure;
/// it only reads `remaining` to warn when the student is about to run out.
struct Quota: Decodable, Equatable {
    var freeLeft: Int?
    var freePerDay: Int?
    var packLeft: Int?
    var canAsk: Bool?

    var remaining: Int? {
        guard let free = freeLeft else { return nil }
        return free + (packLeft ?? 0)
    }
}

struct AlertsResponse: Decodable {
    let alerts: [AlertItem]
    let unread: Int
}

struct AlertItem: Decodable, Identifiable, Equatable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let emoji: String?
    let createdAt: Date
    let readAt: Date?
    let path: String
    var isUnread: Bool { readAt == nil }
}

enum HebrewDate {
    private static let lesson: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = "EEEE, d בMMMM · HH:mm"
        return f
    }()
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func format(_ pattern: String, _ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = pattern
        return f.string(from: d)
    }

    /// "רביעי" (no "יום" prefix).
    static func weekday(_ d: Date) -> String {
        let full = format("EEEE", d)
        return full.hasPrefix("יום ") ? String(full.dropFirst(4)) : full
    }

    static func dayNumber(_ d: Date) -> String { format("d", d) }
    static func time(_ d: Date) -> String { format("HH:mm", d) }

    /// "יום רביעי, 5 בנובמבר"
    static func longDay(_ d: Date) -> String { format("EEEE, d בMMMM", d) }

    /// "17:30–19:00"
    static func timeRange(_ start: Date, minutes: Int) -> String {
        // Wrapped in an LTR isolate, otherwise the Hebrew layout prints the two times in reverse order.
        "\u{2066}\(time(start))–\(time(start.addingTimeInterval(Double(minutes) * 60)))\u{2069}"
    }

    /// "היום", "מחר", or the weekday and date.
    static func dayLabel(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "היום" }
        if Calendar.current.isDateInTomorrow(d) { return "מחר" }
        return format("EEEE, d בMMMM", d)
    }

    static func lessonText(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "היום · \(time.string(from: d))"
            : Calendar.current.isDateInTomorrow(d) ? "מחר · \(time.string(from: d))"
            : lesson.string(from: d)
    }

    /// "בעוד 15 דק׳", "לפני שעה", "בעוד יומיים". (The system formatter appends a stray "(1)" in Hebrew.)
    static func relative(_ d: Date, now: Date = Date()) -> String {
        let seconds = d.timeIntervalSince(now)
        let magnitude = abs(seconds)
        let minutes = Int(magnitude / 60), hours = Int(magnitude / 3600), days = Int(magnitude / 86400)
        if minutes < 1 { return "עכשיו" }
        let amount: String
        if minutes < 60 {
            amount = "\(minutes) דק׳"
        } else if hours < 24 {
            amount = hours == 1 ? "שעה" : hours == 2 ? "שעתיים" : "\(hours) שעות"
        } else {
            amount = days == 1 ? "יום" : days == 2 ? "יומיים" : "\(days) ימים"
        }
        return (seconds > 0 ? "בעוד " : "לפני ") + amount
    }
}
