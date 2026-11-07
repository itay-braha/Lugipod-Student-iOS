import SwiftUI

/// Text that typesets formulas only when it has any (a web view per choice would be wasteful for plain words).
struct RichText: View {
    let text: String
    var font: Font = .heebo(16, 600)
    var color: Color = Theme.ink

    var body: some View {
        if text.contains("$") {
            MathText(text: text)
        } else {
            Text(text).font(font).foregroundStyle(color).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DailyChallengeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var home: HomeModel
    @StateObject private var model = DailyModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(ScreenBackground())
        .task { await model.load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("האתגר היומי").font(.heebo(26, 800)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.heebo(13, 600)).foregroundStyle(Theme.slate500)
            }
            Spacer()
            Pill(text: "🔥 \(model.streak)", fg: Theme.amber800, bg: Theme.amber100)
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
    }

    private var subtitle: String {
        guard let p = model.payload else { return " " }
        let name = p.subject?.name ?? ""
        switch model.phase {
        case .ready: return "\(name) · שאלה \(model.index + 1) מתוך \(model.total)"
        case .finished: return "\(name) · סיימתם"
        default: return name
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ScrollView {
                EmptyState(pose: .peek, title: "משהו לא נטען", message: message, actionTitle: "נסו שוב") {
                    Task { await model.load() }
                }
                .padding(20)
            }
        case .empty:
            ScrollView {
                EmptyState(pose: .sit, title: "עדיין אין שאלות", message: "כשיהיו שאלות מתאימות למקצוע ולרמה שלכם הן יופיעו כאן. אפשר בינתיים לשאול את לוגי בלוגיצ׳אט.",
                           actionTitle: "ללוגיצ׳אט") { router.tab = .lugichat }
                    .padding(20)
            }
        case .ready:
            question
        case .finished:
            finished
        }
    }

    // MARK: A question

    private var question: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    progress
                    if let q = model.question {
                        RichText(text: q.prompt, font: .heebo(19, 700))
                            .padding(18)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
                        ForEach(model.order, id: \.self) { original in
                            choice(q.choices[original], original: original)
                        }
                    }
                    if let error = model.pickError {
                        Text(error).font(.heebo(14, 600)).foregroundStyle(Theme.rose600)
                    }
                    if let r = model.result { feedback(r).id("feedback") }
                    Color.clear.frame(height: 20).id("end")
                }
                .padding(.horizontal, 16).padding(.top, 4)
            }
            .onChange(of: model.result?.explanation) { _, _ in withAnimation { proxy.scrollTo("end") } }
        }
    }

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<model.total, id: \.self) { i in
                Capsule()
                    .fill(i < model.index ? Theme.emerald500 : (i == model.index ? Theme.brand500 : Theme.slate200))
                    .frame(height: 6)
            }
        }
    }

    private func choice(_ text: String, original: Int) -> some View {
        let answered = model.result != nil
        let isPicked = model.picked == original
        let isCorrect = model.result?.answerIndex == original
        let tint: (fg: Color, bg: Color, border: Color) = {
            if answered && isCorrect { return (Theme.emerald700, Theme.emerald50, Theme.emerald500) }
            if answered && isPicked { return (Theme.rose600, Theme.rose50, Theme.rose500) }
            return (Theme.ink, .white, Theme.slate200)
        }()
        return Button { Task { await model.pick(original) } } label: {
            HStack(spacing: 10) {
                RichText(text: text, font: .heebo(17, 600), color: tint.fg)
                if answered && isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.emerald500) }
                else if answered && isPicked { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.rose500) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.border, lineWidth: answered && (isCorrect || isPicked) ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that would grey out the green correct answer too. The model ignores taps once an answer is in.
        .allowsHitTesting(!answered && !model.checking)
    }

    private func feedback(_ r: DailyAnswer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(r.correct ? "כל הכבוד! 🎉" : "לא בדיוק. זה בסדר, ככה לומדים.")
                .font(.heebo(18, 800)).foregroundStyle(r.correct ? Theme.emerald700 : Theme.amber800)
            if !r.explanation.isEmpty {
                RichText(text: r.explanation, font: .heebo(15, 500), color: Theme.slate700)
            }
            Button(model.isLast ? "לסיכום" : "השאלה הבאה") { model.next() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, fill: r.correct ? Theme.emerald50 : Theme.amber50, border: r.correct ? Theme.emerald200 : Theme.amber200)
    }

    // MARK: Done

    private var finished: some View {
        ScrollView {
            VStack(spacing: 16) {
                Lugi(pose: model.correctCount * 2 >= model.total ? .cheer : .proud, height: 150).padding(.top, 10)
                Text("\(model.correctCount) מתוך \(model.total) נכונות").font(.heebo(26, 800)).foregroundStyle(Theme.ink)
                Text(model.streak > 0 ? "הרצף שלכם: \(model.streak) ימים 🔥" : "מחר ממשיכים")
                    .font(.heebo(16, 600)).foregroundStyle(Theme.slate600)
                VStack(spacing: 10) {
                    Button("עוד סבב") { Task { await model.load() } }.buttonStyle(PrimaryButtonStyle())
                    Button("שאלה על משהו אחר? ללוגיצ׳אט") { router.tab = .lugichat }.buttonStyle(SecondaryButtonStyle())
                    Button("מבחן רמה ועוד באתר") { router.open(path: "/dashboard") }
                        .font(.heebo(14, 700)).foregroundStyle(Theme.slate600).padding(.top, 4)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
    }
}
