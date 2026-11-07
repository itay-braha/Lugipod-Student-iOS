import SwiftUI

/// The next-lesson offer ("Encore"): the website's banner, as a card. The same server routes, called with the app's token.
enum Rebook {
    static func active() async -> ActiveRebook? {
        #if DEBUG
        if PreviewMode.screen == "post-lesson-encore" || PreviewMode.screen == "home" { return PreviewMode.rebook() }
        #endif
        guard let data = try? await API.request("GET", "/api/rebook/active"),
              let r = try? API.decoder.decode(ActiveRebookResponse.self, from: data),
              let a = r.active, a.myResponse == "pending" else { return nil }
        return a
    }

    /// Returns the proposal's new status ("confirmed", "pending", "open"...), or nil when the call failed.
    static func respond(_ a: ActiveRebook, yes: Bool) async -> String? {
        guard let data = try? await API.request("POST", "/api/rebook/respond", json: ["proposalId": a.proposalId, "choice": yes ? "yes" : "no"]),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (obj["status"] as? String) ?? "ok"
    }
}

/// "Same time next week?": who already said yes, and two buttons. Shown on Home while an offer is open and right after a lesson.
struct EncoreCardView: View {
    let rebook: ActiveRebook
    var onAnswered: () -> Void
    @EnvironmentObject private var celebration: CelebrationCenter
    @State private var busy = false

    private var others: [ActiveRebook.Peer] { rebook.peers.filter { !$0.isMe } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rebook.isNearMiss
                 ? "\(rebook.emoji) שומרים על החבורה\(rebook.teacherName.map { " והמורה \($0)" } ?? "")!"
                 : "\(rebook.emoji) היה שיעור מעולה! ממשיכים באותו זמן שבוע הבא?")
                .font(.heebo(18, 800)).foregroundStyle(Theme.amber800)
            if rebook.isNearMiss, let slot = rebook.proposedSlotLabel {
                Text("כדי להישאר יחד צריך למתוח קצת את הזמן ל\(slot)\(rebook.originalSlotLabel.map { " (במקום \($0))" } ?? ""). מתאים לכם?")
                    .font(.heebo(14, 500)).foregroundStyle(Theme.amber800)
            } else {
                let yes = others.filter { $0.response == "yes" }.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
                let waiting = others.filter { $0.response != "yes" }.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
                Text(yes.isEmpty ? "תהיו הראשונים לאשר ונשמור את המקומות לחברים שלכם!"
                     : "\(yes.joined(separator: ", ")) אישרו הגעה\(waiting.isEmpty ? "" : " · מחכים ל\(waiting.joined(separator: ", "))")")
                    .font(.heebo(14, 500)).foregroundStyle(Theme.amber800)
            }
            HStack(spacing: 10) {
                Button { Task { await answer(true) } } label: {
                    HStack { if busy { ProgressView().tint(.white) }; Text("כן, שריינו לי מקום") }
                }
                .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.amber500))
                Button("לא הפעם") { Task { await answer(false) } }
                    .font(.heebo(14, 700)).foregroundStyle(Theme.slate500)
            }
            .disabled(busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, fill: Theme.amber50, border: Theme.amber200)
    }

    private func answer(_ yes: Bool) async {
        busy = true
        defer { busy = false }
        let status = await Rebook.respond(rebook, yes: yes)
        if yes, status != nil {
            let confirmed = status == "confirmed"
            celebration.fox(confirmed ? "השיעור מוזמן! 🎉" : "שמרנו לך מקום!", subtitle: confirmed ? "נתראה שבוע הבא" : "נעדכן כשכולם יאשרו", pose: .cheer, big: confirmed)
        }
        onAnswered()
    }
}

/// What the student sees the moment a lesson is over: how was it, then (when there is one) the offer for next week. Done in the app, where
/// they are right then and most likely to answer. Feedback goes to the same place as the website's form.
struct PostLessonFlow: View {
    let kind: String
    let ref: String
    let leftEarly: Bool
    let teacherName: String?
    var onDone: () -> Void

    @EnvironmentObject private var celebration: CelebrationCenter
    private enum Step: Equatable { case feedback, encore(ActiveRebook), done }
    @State private var step: Step = .feedback
    @State private var rating = 0
    @State private var helped: Bool?
    @State private var comment = ""
    @State private var busy = false
    @State private var offer: ActiveRebook?
    @FocusState private var typing: Bool

    var body: some View {
        ZStack {
            Color(hex: 0x0B1020).opacity(0.94).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Lugi(pose: step == .feedback ? .peek : .cheer, height: 120).padding(.top, 24)
                    switch step {
                    case .feedback: feedback
                    case .encore(let r): EncoreCardView(rebook: r) { onDone() }
                    case .done: EmptyView()
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.light)
        .task { offer = await Rebook.active() }
        .onAppear {
            #if DEBUG
            if PreviewMode.screen == "post-lesson-encore", let r = PreviewMode.rebook() { step = .encore(r) }
            #endif
        }
    }

    private var feedback: some View {
        VStack(spacing: 14) {
            Text(leftEarly ? "יצאת מהשיעור מוקדם. הכול בסדר?" : "איך היה השיעור?")
                .font(.heebo(22, 800)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text(teacherName.map { "המשוב שלך על \($0) עוזר לנו להשתפר, והוא אנונימי." } ?? "המשוב שלך עוזר לנו להשתפר, והוא אנונימי.")
                .font(.heebo(14, 500)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { rating = n }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: rating >= n ? "star.fill" : "star")
                            .font(.system(size: 34)).foregroundStyle(rating >= n ? Theme.amber400 : Theme.slate300)
                            .scaleEffect(rating == n ? 1.18 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) כוכבים")
                }
            }
            .environment(\.layoutDirection, .leftToRight)

            Text("הבנת את מה שרצית?").font(.heebo(14, 700)).foregroundStyle(Theme.slate600)
            HStack(spacing: 10) {
                choice("כן, עזר 👍", on: helped == true, tint: Theme.emerald500) { helped = true }
                choice("לא ממש 🤔", on: helped == false, tint: Theme.amber500) { helped = false }
            }

            TextField("עוד משהו שתרצו לספר לנו? (רשות)", text: $comment, axis: .vertical)
                .lineLimit(2...4).font(.heebo(16, 500)).focused($typing)
                .padding(12).background(Theme.slate50, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button { Task { await send() } } label: { HStack { if busy { ProgressView().tint(.white) }; Text("שליחה") } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            Button("דילוג") { advance(thanks: false) }.font(.heebo(14, 700)).foregroundStyle(Theme.slate500)
        }
        .card(padding: 20, radius: 28)
    }

    private func choice(_ text: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.heebo(15, 700)).foregroundStyle(on ? tint : Theme.slate600)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(on ? tint.opacity(0.12) : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? tint : Theme.slate200, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func send() async {
        busy = true
        defer { busy = false }
        var body: [String: Any] = ["kind": kind, "ref": ref, "leftEarly": leftEarly, "comment": comment]
        if rating > 0 { body["rating"] = rating }
        if let helped { body["helped"] = helped }
        _ = try? await API.request("POST", "/api/meeting/feedback", json: body)   // never blocks the exit: feedback is best-effort
        advance(thanks: true)
    }

    private func advance(thanks: Bool) {
        if thanks { celebration.fox("תודה! 💜", subtitle: nil, pose: .proud) }
        if let offer { withAnimation { step = .encore(offer) } } else { onDone() }
    }
}
