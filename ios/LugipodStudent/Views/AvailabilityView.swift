import SwiftUI

@MainActor
final class AvailabilityModel: ObservableObject {
    @Published var slots: Set<Int> = []
    @Published private(set) var loaded = false
    @Published private(set) var saving = false
    @Published var error: String?
    private var original: Set<Int> = []

    var dirty: Bool { slots != original }

    func load() async {
        #if DEBUG
        if PreviewMode.isOn {
            slots = Set([1, 2, 4].flatMap { d in (32...37).map { d * 48 + $0 } })
            original = slots; loaded = true
            return
        }
        #endif
        struct Reply: Decodable { let slots: [Int] }
        do {
            let raw = try await API.request("GET", "/api/native/student/availability")
            slots = Set(try API.decoder.decode(Reply.self, from: raw).slots)
            original = slots
            loaded = true
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            self.error = "לא הצלחנו לטעון את השעות. בדקו חיבור ונסו שוב."
        }
    }

    func save() async -> Bool {
        saving = true; error = nil
        defer { saving = false }
        do {
            _ = try await API.request("POST", "/api/native/student/availability", json: ["slots": slots.sorted()])
            original = slots
            return true
        } catch {
            self.error = "לא הצלחנו לשמור. נסו שוב."
            return false
        }
    }
}

/// "My hours": paint the half-hours that suit you, with a finger. The same data and the same save as the website's availability card
/// (slot = day × 48 + half-hour), so a group can be found for the times you marked.
struct AvailabilityView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AvailabilityModel()
    @State private var paintAdding: Bool?

    private let firstRow = 18          // 09:00
    private let rows = 26              // until 22:00
    private let rowH: CGFloat = 30
    private let labelW: CGFloat = 46
    private let dayNames = ["א", "ב", "ג", "ד", "ה", "ו", "ש"]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    Text("לחצו או גררו על השעות שנוח לכם ללמוד. ככל שתסמנו יותר שעות רצופות, נמצא לכם קבוצה מהר יותר.")
                        .font(.heebo(14, 600)).foregroundStyle(Theme.slate600).frame(maxWidth: .infinity, alignment: .leading)
                    if model.loaded { grid } else if let e = model.error { Text(e).font(.heebo(14, 700)).foregroundStyle(Theme.rose600) } else { ProgressView().padding(40) }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ScreenBackground())
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("סגירה") { dismiss() }.buttonStyle(SoftButtonStyle(fg: .white, bg: Color.white.opacity(0.22)))
            Spacer()
            VStack(spacing: 0) {
                Text("השעות שלי").font(.heebo(22, 900)).foregroundStyle(.white)
                Text("\(hours) שעות בשבוע").font(.heebo(12, 800)).foregroundStyle(Theme.gold300)
            }
            Spacer()
            Button { Task { if await model.save() { UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() } } } label: {
                HStack(spacing: 6) { if model.saving { ProgressView().tint(.white) }; Text("שמירה") }
            }
            .buttonStyle(SoftButtonStyle(fg: .white, bg: Theme.orange500))
            .disabled(!model.dirty || model.saving)
            .opacity(model.dirty ? 1 : 0.55)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .background {
            Theme.hero.clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                .shadow(color: Theme.brand800.opacity(0.3), radius: 10, y: 5)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var hours: String {
        let h = Double(model.slots.count) / 2
        return h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)
    }

    /// Days run right to left (Sunday on the right), so the grid is laid out left to right and the day order reversed.
    private var grid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach((0..<7).reversed(), id: \.self) { d in
                    Text(dayNames[d]).font(.heebo(14, 900)).foregroundStyle(Theme.brand700).frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: labelW, height: 1)
            }
            GeometryReader { geo in
                let colW = (geo.size.width - labelW) / 7
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach((0..<7).reversed(), id: \.self) { d in
                                    let on = model.slots.contains(d * 48 + firstRow + r)
                                    Rectangle()
                                        .fill(on ? AnyShapeStyle(Theme.indigoButton) : AnyShapeStyle(Color.white))
                                        .overlay(Rectangle().strokeBorder((r % 2 == 0 ? Theme.slate300 : Theme.slate100), lineWidth: 0.5))
                                        .frame(width: colW, height: rowH)
                                }
                                Text(r % 2 == 0 ? String(format: "%02d:00", (firstRow + r) / 2) : "")
                                    .font(.heebo(11, 700)).foregroundStyle(Theme.slate500).frame(width: labelW, height: rowH)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in paint(at: v.location, colW: colW) }.onEnded { _ in paintAdding = nil })
            }
            .frame(height: rowH * CGFloat(rows))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.brand200, lineWidth: 1.5))
            if let e = model.error { Text(e).font(.heebo(13, 700)).foregroundStyle(Theme.rose600) }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func paint(at p: CGPoint, colW: CGFloat) {
        guard p.x >= 0, p.x < colW * 7, p.y >= 0, p.y < rowH * CGFloat(rows) else { return }
        let col = min(6, Int(p.x / colW))
        let day = 6 - col
        let row = min(rows - 1, Int(p.y / rowH))
        let slot = day * 48 + firstRow + row
        if paintAdding == nil { paintAdding = !model.slots.contains(slot); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        if paintAdding == true { model.slots.insert(slot) } else { model.slots.remove(slot) }
    }
}
