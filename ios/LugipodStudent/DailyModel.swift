import SwiftUI
import UIKit

struct DailyQuestion: Decodable, Identifiable, Equatable {
    let id: String
    let prompt: String
    let choices: [String]
}

struct DailyPayload: Decodable {
    struct Subject: Decodable, Equatable { let id: String; let name: String }
    let subject: Subject?
    let level: String?
    let questions: [DailyQuestion]
    let doneToday: Bool
    let streak: Int
}

struct DailyAnswer: Decodable {
    let correct: Bool
    let answerIndex: Int?
    let explanation: String
    let streak: Int?
}

/// The daily challenge, natively. The server sends the questions WITHOUT answers and checks each pick (it also records the attempt
/// as skill evidence and completes the day on a correct answer), so nothing the app holds can reveal an answer.
@MainActor
final class DailyModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, finished, empty, failed(String) }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var payload: DailyPayload?
    @Published private(set) var index = 0
    /// Display order of the current question's choices (indexes into `choices`), shuffled once per question.
    @Published private(set) var order: [Int] = []
    @Published private(set) var picked: Int?          // original index of the choice the student tapped
    @Published private(set) var result: DailyAnswer?
    @Published private(set) var checking = false
    @Published private(set) var correctCount = 0
    @Published private(set) var streak = 0
    @Published var pickError: String?

    private var shownAt = Date()

    var question: DailyQuestion? {
        guard let q = payload?.questions, index < q.count else { return nil }
        return q[index]
    }
    var total: Int { payload?.questions.count ?? 0 }
    var isLast: Bool { index + 1 >= total }

    func load() async {
        phase = .loading
        pickError = nil
        do {
            let p = try await API.get("/api/native/student/daily", as: DailyPayload.self)
            payload = p
            streak = p.streak
            index = 0; correctCount = 0; picked = nil; result = nil
            if p.questions.isEmpty { phase = .empty } else { phase = .ready; startQuestion() }
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch APIError.notAStudent {
            phase = .failed("החשבון הזה אינו חשבון תלמיד.")
        } catch {
            phase = .failed("לא הצלחנו לטעון את האתגר. בדקו חיבור ונסו שוב.")
        }
    }

    private func startQuestion() {
        guard let q = question else { return }
        order = Array(q.choices.indices).shuffled()
        picked = nil; result = nil; pickError = nil
        shownAt = Date()
        #if DEBUG
        if PreviewMode.screen == "daily-answered" { Task { await pick(order[0]) } }
        #endif
    }

    func pick(_ original: Int) async {
        guard let q = question, picked == nil, !checking else { return }
        checking = true; pickError = nil
        defer { checking = false }
        do {
            let ms = Int(Date().timeIntervalSince(shownAt) * 1000)
            let data = try await API.request("POST", "/api/native/student/daily/answer",
                                             json: ["questionId": q.id, "choiceIndex": original, "responseMs": ms])
            let answer = try API.decoder.decode(DailyAnswer.self, from: data)
            picked = original
            result = answer
            if answer.correct { correctCount += 1 }
            if let s = answer.streak { streak = s }
            UINotificationFeedbackGenerator().notificationOccurred(answer.correct ? .success : .error)
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            pickError = "לא הצלחנו לשמור את התשובה. נסו שוב."
        }
    }

    func next() {
        if isLast { phase = .finished; return }
        index += 1
        startQuestion()
    }
}
