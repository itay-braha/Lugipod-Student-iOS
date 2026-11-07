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
    @State private var scope: Scope = .group
    @State private var metric: Metric = .streak
    @State private var peer: Peer?
    @State private var showPhone = false
    @State private var note: String?

    private enum Scope: String, CaseIterable { case group = "הקבוצה שלי", friends = "החברים שלי" }
    private enum Metric: String, CaseIterable { case streak = "🔥 רצף", points = "⭐ נקודות" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(spacing: 16) {
                    if let note { Text(note).font(.heebo(14, 700)).foregroundStyle(Theme.brand700).frame(maxWidth: .infinity, alignment: .leading) }
                    requests
                    controls
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
                    Text("מתחרים ברצף ובנקודות, ולומדים יחד").font(.heebo(13, 700)).foregroundStyle(.white.opacity(0.92))
                }
                Spacer()
            }
            HStack(spacing: 10) {
                if let invite = model.data?.invite {
                    ShareLink(item: invite.text) { Label("הזמנת חברים", systemImage: "square.and.arrow.up") }
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

    // MARK: Segment controls

    private var controls: some View {
        VStack(spacing: 10) {
            segmented(Scope.allCases, selection: $scope) { $0.rawValue }
            segmented(Metric.allCases, selection: $metric) { $0.rawValue }
        }
    }

    private func segmented<T: Hashable>(_ items: [T], selection: Binding<T>, label: @escaping (T) -> String) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let on = selection.wrappedValue == item
                Button { withAnimation(.easeOut(duration: 0.15)) { selection.wrappedValue = item } } label: {
                    Text(label(item)).font(.heebo(14, on ? 900 : 700)).foregroundStyle(on ? .white : Theme.brand700)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(on ? AnyShapeStyle(Theme.indigoButton) : AnyShapeStyle(Theme.brand50), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Leaderboards

    @ViewBuilder private var boards: some View {
        if let data = model.data {
            if scope == .group {
                if data.groups.isEmpty {
                    EmptyState(pose: .sit, title: "עוד אין קבוצה", message: "כשתשובצו לקבוצה, תוכלו להתחרות כאן עם מי שלומד איתכם.")
                }
                ForEach(data.groups) { g in
                    board(title: g.title, people: g.members.map { var p = $0; p.isFriend = model.friendIds.contains(p.id); return p }, me: data.me)
                }
            } else {
                if data.friends.isEmpty {
                    friendsEmpty
                } else {
                    board(title: "החברים שלי", people: data.friends, me: data.me)
                }
            }
        } else if let error = model.error {
            EmptyState(pose: .peek, title: "משהו לא נטען", message: error, actionTitle: "נסו שוב") { Task { await model.load() } }
        } else {
            ProgressView().padding(.top, 30)
        }
    }

    private var friendsEmpty: some View {
        VStack(spacing: 12) {
            Lugi(pose: .wave, height: 120)
            Text("עוד אין חברים באפליקציה").font(.heebo(20, 900)).foregroundStyle(Theme.ink)
            Text("הזמינו חברים וצאו לדרך: מי יחזיק רצף ארוך יותר? אפשר גם להוסיף מי שלומד איתכם בקבוצה, בלחיצה עליו.")
                .font(.heebo(14, 600)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)
            if let invite = model.data?.invite {
                ShareLink(item: invite.text) { Label("הזמנת חברים", systemImage: "square.and.arrow.up") }.buttonStyle(CTAButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20, radius: 26)
    }

    private func value(_ p: Peer) -> Int { metric == .streak ? p.streak : p.points }

    private func board(title: String, people: [Peer], me: Peer?) -> some View {
        let all = ((me.map { [$0] } ?? []) + people).sorted { value($0) > value($1) }
        return VStack(spacing: 10) {
            SectionTitle(text: title)
            VStack(spacing: 0) {
                ForEach(Array(all.enumerated()), id: \.element.id) { i, p in
                    Button { peer = p } label: { row(rank: i + 1, p, isMe: p.id == me?.id) }.buttonStyle(.plain)
                    if i < all.count - 1 { Divider().padding(.horizontal, 14) }
                }
            }
            .card(padding: 4, radius: 22)
        }
    }

    private func row(rank: Int, _ p: Peer, isMe: Bool) -> some View {
        HStack(spacing: 12) {
            Text(rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : "\(rank)")
                .font(.heebo(rank <= 3 ? 22 : 15, 900)).foregroundStyle(Theme.slate500).frame(width: 30)
            AvatarView(name: p.name, avatar: p.avatar, frame: p.frame, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isMe ? "\(p.name) (אתם)" : p.name).font(.heebo(16, 800)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                if let t = p.title { TitleChip(title: t) }
            }
            Spacer(minLength: 6)
            Text(metric == .streak ? "🔥 \(p.streak)" : "⭐ \(p.points)")
                .font(.heebo(18, 900)).foregroundStyle(metric == .streak ? Theme.orange600 : Theme.brand700)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isMe ? Theme.brand50 : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
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
