import SwiftUI
import UIKit

struct DailyQuestion: Decodable, Identifiable, Equatable {
    let id: String
    let prompt: String
    let choices: [String]
    let answerIndex: Int
    let explanation: String
}

struct DailyPayload: Decodable {
    struct Subject: Decodable, Equatable { let id: String; let name: String }
    let subject: Subject?
    let level: String?
    let questions: [DailyQuestion]
    let doneToday: Bool
    let streak: Int
}

/// What the student sees the moment a choice is tapped.
struct DailyResult: Equatable {
    let correct: Bool
    let answerIndex: Int
    let explanation: String
}

/// The daily challenge, natively. The questions arrive with their answers (as on the website), so right/wrong shows the instant a choice
/// is tapped; each attempt is then sent to the server in the background, which re-checks it, stores it as skill evidence and completes
/// the day on a correct answer. A lost connection costs nothing: the send is retried a few times.
@MainActor
final class DailyModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, finished, empty, failed(String) }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var payload: DailyPayload?
    @Published private(set) var index = 0
    /// Display order of the current question's choices (indexes into `choices`), shuffled once per question.
    @Published private(set) var order: [Int] = []
    @Published private(set) var picked: Int?
    @Published private(set) var result: DailyResult?
    @Published private(set) var correctCount = 0
    @Published private(set) var streak = 0

    private var shownAt = Date()
    private var loadedAt: Date?

    var question: DailyQuestion? {
        guard let q = payload?.questions, index < q.count else { return nil }
        return q[index]
    }
    var total: Int { payload?.questions.count ?? 0 }
    var isLast: Bool { index + 1 >= total }

    /// Called at launch so the first question is already there when the student opens the tab.
    func loadIfNeeded() async {
        if let at = loadedAt, Date().timeIntervalSince(at) < 1800, phase != .loading { return }
        if phase == .ready, picked != nil { return }          // never reshuffle under someone who is answering
        await load()
    }

    func load() async {
        if payload == nil { phase = .loading }
        do {
            let raw = try await API.request("GET", "/api/native/student/daily")
            apply(try API.decoder.decode(DailyPayload.self, from: raw))
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch APIError.notAStudent {
            phase = .failed("החשבון הזה אינו חשבון תלמיד.")
        } catch {
            if payload == nil { phase = .failed("לא הצלחנו לטעון את האתגר. בדקו חיבור ונסו שוב.") }
        }
    }

    /// Starts a round from a payload (what `load` does after the server answers; also how the tests feed it).
    func apply(_ p: DailyPayload) {
        payload = p
        streak = p.streak
        loadedAt = Date()
        index = 0; correctCount = 0; picked = nil; result = nil
        if p.questions.isEmpty { phase = .empty } else { phase = .ready; startQuestion() }
    }

    private func startQuestion() {
        guard let q = question else { return }
        order = Array(q.choices.indices).shuffled()
        picked = nil; result = nil
        shownAt = Date()
        #if DEBUG
        if PreviewMode.screen == "daily-answered" { pick(order[0]) }
        #endif
    }

    func pick(_ original: Int) {
        guard let q = question, picked == nil else { return }
        let correct = original == q.answerIndex
        picked = original
        result = DailyResult(correct: correct, answerIndex: q.answerIndex, explanation: q.explanation)
        if correct {
            correctCount += 1
            if payload?.doneToday == false, correctCount == 1 { streak += 1 }   // shown at once; the server's number replaces it
        }
        UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
        let ms = Int(Date().timeIntervalSince(shownAt) * 1000)
        Task { await record(question: q.id, choice: original, ms: ms) }
    }

    func next() {
        if isLast { phase = .finished; return }
        index += 1
        startQuestion()
    }

    private struct Ack: Decodable { let streak: Int? }

    private func record(question id: String, choice: Int, ms: Int) async {
        for attempt in 0..<4 {
            do {
                let data = try await API.request("POST", "/api/native/student/daily/answer", json: ["questionId": id, "choiceIndex": choice, "responseMs": ms])
                if let s = (try? API.decoder.decode(Ack.self, from: data))?.streak { streak = s }
                return
            } catch APIError.notSignedIn {
                return
            } catch {
                try? await Task.sleep(nanoseconds: UInt64(2_000_000_000 * (attempt + 1)))
            }
        }
    }
}
