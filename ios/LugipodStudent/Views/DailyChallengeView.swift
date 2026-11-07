import SwiftUI

struct DailyChallengeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var model: DailyModel
    @EnvironmentObject private var celebration: CelebrationCenter

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(ScreenBackground())
        .task { await model.loadIfNeeded() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("🔥").font(.system(size: 30))
                .frame(width: 54, height: 54).background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("האתגר היומי").font(.heebo(25, 900)).foregroundStyle(.white)
                Text(subtitle).font(.heebo(13, 700)).foregroundStyle(.white.opacity(0.92))
            }
            Spacer()
            VStack(spacing: 0) {
                Text("\(model.streak)").font(.heebo(24, 900)).foregroundStyle(.white)
                Text("ימים ברצף").font(.heebo(10, 800)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [Theme.orange400, Theme.orange600, Color(hex: 0xDC2626)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Theme.gold300.opacity(0.5), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
            .shadow(color: Theme.orange700.opacity(0.35), radius: 14, y: 7)
            .ignoresSafeArea(edges: .top)
        }
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
                    if let r = model.result { feedback(r).id("feedback") }
                    Color.clear.frame(height: 20).id("end")
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 16).padding(.top, 4)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.result) { _, r in
                guard let r else { return }
                withAnimation { proxy.scrollTo("end") }
                if r.correct {
                    // A 10-day streak gets the big one; every other right answer a short cheer.
                    let milestone = model.streak > 0 && model.streak % 10 == 0 && model.correctCount == 1
                    celebration.fox(milestone ? "רצף של \(model.streak) ימים! 🎉" : "כל הכבוד! 🔥",
                                    subtitle: milestone ? "זכית בלוגי מתנה 🪙" : (model.correctCount == 1 ? "שמרת על הרצף · +5 נקודות" : nil),
                                    pose: milestone ? .cheer : .praise, big: milestone)
                }
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(0..<model.total, id: \.self) { i in
                Capsule()
                    .fill(i < model.index ? Theme.emerald500 : (i == model.index ? Theme.orange500 : Theme.slate300))
                    .frame(height: 8)
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
            return (Theme.ink, .white, Theme.brand300)
        }()
        return Button { model.pick(original) } label: {
            HStack(spacing: 12) {
                // the choice's letter, in a solid disc (it turns green / red with the answer)
                Text(letter(for: original)).font(.heebo(15, 900)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(answered && isCorrect ? Theme.emerald500 : (answered && isPicked ? Theme.rose500 : Theme.brand500), in: Circle())
                RichText(text: text, font: .heebo(17, 700), color: tint.fg)
                if answered && isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.emerald500) }
                else if answered && isPicked { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.rose500) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(answered ? tint.border : Theme.brand200, lineWidth: answered && (isCorrect || isPicked) ? 3 : 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!answered)
    }

    private func letter(for original: Int) -> String {
        let order = model.order.firstIndex(of: original) ?? original
        return ["א", "ב", "ג", "ד", "ה", "ו"][min(order, 5)]
    }

    private func feedback(_ r: DailyResult) -> some View {
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
                .frame(maxWidth: 420)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
        }
    }
}
