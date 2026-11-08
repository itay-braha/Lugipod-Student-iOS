import SwiftUI

// MARK: - Model

@MainActor
final class FriendsModel: ObservableObject {
    @Published private(set) var data: FriendsResponse?
    @Published var error: String?

    init() {
        #if DEBUG
        if PreviewMode.isOn { return }
        #endif
        if let raw = LocalCache.read("friends"), let cached = try? API.decoder.decode(FriendsResponse.self, from: raw) { data = cached }
    }

    func load() async {
        do {
            let raw = try await API.request("GET", "/api/native/student/friends")
            data = try API.decoder.decode(FriendsResponse.self, from: raw)
            LocalCache.write("friends", raw)
            error = nil
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            if data == nil { self.error = "לא הצלחנו לטעון את החברים. בדקו חיבור ונסו שוב." }
        }
    }

    /// One action (request, respond, remove, phone); returns an error message or nil, and refreshes the lists.
    @discardableResult
    func act(_ body: [String: Any]) async -> String? {
        do {
            _ = try await API.request("POST", "/api/native/student/friends", json: body)
            await load()
            return nil
        } catch APIError.server(_, let message) where !message.isEmpty {
            return message
        } catch { return "לא הצלחנו. נסו שוב." }
    }

    var friendIds: Set<String> { Set(data?.friends.map(\.id) ?? []) }
}

// MARK: - A student, seen by another

/// A peer's card: who they are, their streak and the record, and the points; and add / remove friend.
struct PeerSheet: View {
    let peer: Peer
    let isMe: Bool
    let isFriend: Bool
    let requested: Bool
    var onAdd: () -> Void
    var onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    var body: some View {
        VStack(spacing: 16) {
            AvatarView(name: peer.name, avatar: peer.avatar, frame: peer.frame, size: 92).padding(.top, 8)
            VStack(spacing: 6) {
                Text(peer.name).font(.heebo(26, 900)).foregroundStyle(Theme.ink)
                if let title = peer.title { TitleChip(title: title) }
            }
            HStack(spacing: 10) {
                stat("🔥", "\(peer.streak)", "רצף כרגע", Theme.orange600, Theme.orange100)
                stat("⭐", "\(peer.highestStreak)", "שיא רצף", Theme.amber800, Theme.amber100)
                stat("🏅", "\(peer.points)", "נקודות", Theme.brand700, Theme.brand100)
            }
            if !isMe {
                if isFriend {
                    Label("חברים ✓", systemImage: "person.2.fill").font(.heebo(16, 800)).foregroundStyle(Theme.emerald700)
                    Button("הסרה מהחברים") { confirmRemove = true }.font(.heebo(14, 700)).foregroundStyle(Theme.slate500)
                } else if requested {
                    Label("הבקשה נשלחה", systemImage: "paperplane.fill").font(.heebo(16, 800)).foregroundStyle(Theme.slate600)
                } else {
                    Button { onAdd(); dismiss() } label: { Label("הוספה לחברים", systemImage: "person.badge.plus") }.buttonStyle(CTAButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 8)
        .confirmationDialog("להסיר את \(peer.name) מהחברים?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("הסרה", role: .destructive) { onRemove(); dismiss() }
            Button("ביטול", role: .cancel) {}
        }
    }

    private func stat(_ icon: String, _ value: String, _ label: String, _ fg: Color, _ bg: Color) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.system(size: 22))
            Text(value).font(.heebo(24, 900)).foregroundStyle(fg)
            Text(label).font(.heebo(11, 800)).foregroundStyle(fg.opacity(0.85))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - The friends tab

struct FriendsView: View {
    @EnvironmentObject private var model: FriendsModel
    @State private var peer: Peer?
    @State private var showPhone = false
    @State private var showInvite = false
    @State private var note: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(spacing: 16) {
                    if let note { Text(note).font(.heebo(14, 700)).foregroundStyle(Theme.brand700).frame(maxWidth: .infinity, alignment: .leading) }
                    requests
                    boards
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(ScreenBackground())
        .refreshable { await model.load() }
        .task {
            await model.load()
            #if DEBUG
            if PreviewMode.screen == "peer" { peer = model.data?.groups.first?.members.first }
            if PreviewMode.screen == "invite" { showInvite = true }
            #endif
        }
        .sheet(item: $peer) { p in
            PeerSheet(peer: p, isMe: p.id == model.data?.me?.id, isFriend: model.friendIds.contains(p.id), requested: p.requested == true,
                      onAdd: { Task { note = await model.act(["action": "request", "userId": p.id]) ?? "שלחנו בקשת חברות ל\(p.name) ✓" } },
                      onRemove: { Task { _ = await model.act(["action": "remove", "friendId": p.id]) } })
                .presentationDetents([.fraction(0.62)])
                .presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showInvite) {
            if let invite = model.data?.invite {
                InviteSheet(invite: invite).presentationDetents([.large]).presentationDragIndicator(.visible).environment(\.layoutDirection, .rightToLeft)
            }
        }
        .sheet(isPresented: $showPhone) {
            AddByPhoneSheet { phone in await model.act(["action": "phone", "phone": phone]) }
                .presentationDetents([.medium]).presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    // MARK: Header: title + the invite

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("🤝").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text("חברים").font(.heebo(26, 900)).foregroundStyle(.white)
                    Text("מי חבר/ה שלכם, כמה נקודות ומה שיא הרצף").font(.heebo(13, 700)).foregroundStyle(.white.opacity(0.92))
                }
                Spacer()
            }
            HStack(spacing: 10) {
                if model.data?.invite != nil {
                    Button { showInvite = true } label: { Label("הזמנת חברים · 10 לוגי 🎁", systemImage: "gift.fill") }
                        .buttonStyle(SoftButtonStyle(fg: Theme.orange700, bg: .white))
                }
                Button { showPhone = true } label: { Label("הוספה לפי טלפון", systemImage: "phone.fill") }
                    .buttonStyle(SoftButtonStyle(fg: .white, bg: Color.white.opacity(0.22)))
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, ScreenInsets.top + 12).padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [Color(hex: 0xEC4899), Theme.violet500, Theme.brand500], startPoint: .topTrailing, endPoint: .bottomLeading)
                RadialGradient(colors: [Theme.orange400.opacity(0.5), .clear], center: .bottomLeading, startRadius: 0, endRadius: 260)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
            .shadow(color: Theme.violet700.opacity(0.28), radius: 12, y: 6)
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Requests

    @ViewBuilder private var requests: some View {
        ForEach(model.data?.incoming ?? []) { r in
            HStack(spacing: 12) {
                AvatarView(name: r.from.name, avatar: r.from.avatar, frame: r.from.frame, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(r.from.name) רוצה להיות חבר/ה שלך").font(.heebo(15, 800)).foregroundStyle(Theme.ink)
                    Text("🔥 \(r.from.streak) · ⭐ \(r.from.points)").font(.heebo(12, 700)).foregroundStyle(Theme.slate500)
                }
                Spacer(minLength: 4)
                Button("אישור") { Task { _ = await model.act(["action": "respond", "requestId": r.requestId, "accept": true]) } }
                    .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.emerald600))
                Button { Task { _ = await model.act(["action": "respond", "requestId": r.requestId, "accept": false]) } } label: { Image(systemName: "xmark") }
                    .buttonStyle(SoftButtonStyle(fg: Theme.slate600, bg: Theme.slate100))
            }
            .card(padding: 14, radius: 20, fill: Theme.orange100, border: Theme.orange300)
        }
    }

    // MARK: The list: everyone you are friends with, plus (below) classmates you could add

    @ViewBuilder private var boards: some View {
        if let data = model.data {
            if data.friends.isEmpty { friendsEmpty }
            else { board(title: "החברים שלי", people: data.friends, me: data.me) }
            let mates = classmates(data)
            if !mates.isEmpty {
                VStack(spacing: 10) {
                    SectionTitle(text: "לומדים איתכם בקבוצה", count: mates.count)
                    VStack(spacing: 0) {
                        ForEach(Array(mates.enumerated()), id: \.element.id) { i, p in
                            Button { peer = p } label: { row(rank: nil, p, isMe: false) }.buttonStyle(.plain)
                            if i < mates.count - 1 { Divider().padding(.horizontal, 14) }
                        }
                    }
                    .card(padding: 4, radius: 22)
                    Text("לוחצים על מישהו כדי לראות את הנקודות והשיא שלו, ולהוסיף אותו לחברים.")
                        .font(.heebo(12, 600)).foregroundStyle(Theme.slate500).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if let error = model.error {
            EmptyState(pose: .peek, title: "משהו לא נטען", message: error, actionTitle: "נסו שוב") { Task { await model.load() } }
        } else {
            ProgressView().padding(.top, 30)
        }
    }

    /// People in my groups who are not (yet) friends, each once.
    private func classmates(_ data: FriendsResponse) -> [Peer] {
        var seen = Set(data.friends.map(\.id)); if let me = data.me { seen.insert(me.id) }
        var out: [Peer] = []
        for g in data.groups { for m in g.members where !seen.contains(m.id) { seen.insert(m.id); out.append(m) } }
        return out.sorted { $0.points > $1.points }
    }

    private var friendsEmpty: some View {
        VStack(spacing: 12) {
            Lugi(pose: .wave, height: 120)
            Text("עוד אין חברים באפליקציה").font(.heebo(20, 900)).foregroundStyle(Theme.ink)
            Text("הזמינו חברים ותראו כאן את הנקודות ואת שיא הרצף של כל אחד. אפשר גם להוסיף מי שלומד איתכם בקבוצה, בלחיצה עליו.")
                .font(.heebo(14, 600)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)
            if model.data?.invite != nil {
                Button { showInvite = true } label: { Label("הזמנת חברים · 10 לוגי 🎁", systemImage: "gift.fill") }.buttonStyle(CTAButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20, radius: 26)
    }

    /// Me and my friends, most points first.
    private func board(title: String, people: [Peer], me: Peer?) -> some View {
        let all = ((me.map { [$0] } ?? []) + people).sorted { $0.points > $1.points }
        return VStack(spacing: 10) {
            SectionTitle(text: title, count: people.count)
            VStack(spacing: 0) {
                ForEach(Array(all.enumerated()), id: \.element.id) { i, p in
                    Button { peer = p } label: { row(rank: i + 1, p, isMe: p.id == me?.id) }.buttonStyle(.plain)
                    if i < all.count - 1 { Divider().padding(.horizontal, 14) }
                }
            }
            .card(padding: 4, radius: 22)
        }
    }

    /// Icon, name, points and the highest streak ever.
    private func row(rank: Int?, _ p: Peer, isMe: Bool) -> some View {
        HStack(spacing: 12) {
            if let rank {
                Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : "\(rank)")
                    .font(.heebo(rank <= 3 ? 22 : 15, 900)).foregroundStyle(Theme.slate500).frame(width: 30)
            }
            AvatarView(name: p.name, avatar: p.avatar, frame: p.frame, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(isMe ? "\(p.name) (אתם)" : p.name).font(.heebo(16, 800)).foregroundStyle(Theme.ink).lineLimit(1)
                if let t = p.title { TitleChip(title: t) }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("⭐ \(p.points)").font(.heebo(17, 900)).foregroundStyle(Theme.brand700)
                Text("🔥 שיא \(p.highestStreak)").font(.heebo(12, 800)).foregroundStyle(Theme.orange600)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isMe ? Theme.brand50 : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// What tapping "הזמנת חברים" shows first: the deal, then the share sheet. 10 לוגי (₪200) after the friend's 4 full lessons.
struct InviteSheet: View {
    let invite: FriendsResponse.Invite
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                FoxCoin(size: 96).padding(.top, 8)
                VStack(spacing: 6) {
                    Text("הזמינו חבר/ה וקבלו 10 לוגי").font(.heebo(26, 900)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    Text("200 ₪ ✨*").font(.heebo(20, 900)).foregroundStyle(Theme.orange600)
                }
                VStack(alignment: .leading, spacing: 12) {
                    step("1", "שולחים לחבר/ה את הקישור שלכם")
                    step("2", "הוא/היא מצטרפים ומסיימים 4 שיעורים מלאים")
                    step("3", "אתם מקבלים 10 לוגי (200 ₪) זיכוי בחשבון החודשי, והוא תקף לשנה")
                }
                .card(padding: 16, radius: 22)
                Text("* אם החבר/ה נהנים מהנחה במסגרת ארגון או בית ספר, הסכום יותאם בהתאם.")
                    .font(.heebo(12, 600)).foregroundStyle(Theme.slate500).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                ShareLink(item: invite.text) { Label("שליחת ההזמנה", systemImage: "square.and.arrow.up") }.buttonStyle(CTAButtonStyle())
                Button {
                    UIPasteboard.general.string = invite.link; copied = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: { Label(copied ? "הקישור הועתק ✓" : "העתקת הקישור", systemImage: "link") }
                    .buttonStyle(SoftButtonStyle(fg: Theme.brand700, bg: Theme.brand100))
                Button("סגירה") { dismiss() }.font(.heebo(14, 700)).foregroundStyle(Theme.slate500)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 20).padding(.vertical, 22)
            .frame(maxWidth: .infinity)
        }
        .background(ScreenBackground())
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.heebo(15, 900)).foregroundStyle(.white).frame(width: 30, height: 30).background(Theme.orange500, in: Circle())
            Text(text).font(.heebo(15, 700)).foregroundStyle(Theme.slate700).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct AddByPhoneSheet: View {
    var send: (String) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var busy = false
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("הוספת חבר/ה לפי טלפון").font(.heebo(22, 900)).foregroundStyle(Theme.ink)
            Text("נשלח בקשת חברות למי שכבר באפליקציה עם המספר הזה.").font(.heebo(14, 500)).foregroundStyle(Theme.slate600)
            LugiFieldBox(label: "מספר טלפון", focused: focused) {
                TextField("050-123-4567", text: $phone).keyboardType(.numberPad).font(.heebo(20, 600).monospacedDigit())
                    .environment(\.layoutDirection, .leftToRight).multilineTextAlignment(.leading).focused($focused)
                    .onChange(of: phone) { _, new in let f = Phone.format(new); if f != new { phone = f } }
            }
            if let message { Text(message).font(.heebo(14, 700)).foregroundStyle(Theme.brand700) }
            Button { Task { busy = true; message = await send(Phone.digits(phone)) ?? "הבקשה נשלחה ✓ (אם המספר באפליקציה)"; busy = false } } label: {
                HStack { if busy { ProgressView().tint(.white) }; Text("שליחת בקשה") }
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(!Phone.isValid(phone) || busy)
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear { focused = true }
    }
}
