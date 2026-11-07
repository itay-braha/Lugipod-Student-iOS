import PDFKit
import SwiftUI

// MARK: - A lesson summary (PDF), opened in the app

/// Asks the server for a short-lived link to the teacher's summary file, downloads it, and shows it with the system PDF viewer (zoom, scroll,
/// search, and a share button).
@MainActor
final class PDFLoader: ObservableObject {
    enum State { case loading, ready(URL), failed(String) }
    @Published private(set) var state: State = .loading

    func load(_ file: FileRef) async {
        state = .loading
        do {
            let data = try await API.request("POST", "/api/native/student/material", json: ["id": file.id], timeout: 60)
            struct Reply: Decodable { let url: String }
            guard let url = URL(string: try API.decoder.decode(Reply.self, from: data).url) else { throw APIError.badURL }
            let (tmp, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.badURL }
            let safe = file.name.replacingOccurrences(of: "/", with: "-")
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safe.hasSuffix(".pdf") ? safe : safe + ".pdf")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            guard PDFDocument(url: dest) != nil else { throw APIError.badURL }
            state = .ready(dest)
        } catch APIError.server(_, let message) where !message.isEmpty {
            state = .failed(message)
        } catch {
            state = .failed("לא הצלחנו לפתוח את הקובץ. בדקו חיבור ונסו שוב.")
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(Theme.slate100)
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {}
}

struct PDFSheet: View {
    let file: FileRef
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader = PDFLoader()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("סגירה") { dismiss() }.buttonStyle(SoftButtonStyle(fg: Theme.brand700, bg: Theme.brand50))
                Spacer()
                Text(file.name).font(.heebo(15, 800)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                if case .ready(let url) = loader.state {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(SoftButtonStyle())
                } else { Color.clear.frame(width: 44, height: 1) }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            switch loader.state {
            case .loading:
                VStack(spacing: 12) { ProgressView().controlSize(.large); Text("פותחים את הסיכום…").font(.heebo(14, 700)).foregroundStyle(Theme.slate600) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.ellipsis").font(.system(size: 36)).foregroundStyle(Theme.slate400)
                    Text(message).font(.heebo(15, 700)).foregroundStyle(Theme.slate700).multilineTextAlignment(.center)
                    Button("נסו שוב") { Task { await loader.load(file) } }.buttonStyle(SoftButtonStyle())
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let url):
                PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Color.white)
        .task { await loader.load(file) }
    }
}

/// The buttons that open a lesson's summary files.
struct FileButtons: View {
    let files: [FileRef]
    @State private var open: FileRef?

    var body: some View {
        ForEach(files) { f in
            Button { open = f } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.richtext.fill").foregroundStyle(Theme.rose500)
                    Text(files.count > 1 ? f.name : "סיכום השיעור (PDF)").font(.heebo(14, 800)).foregroundStyle(Theme.brand800).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.brand400)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.brand50, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(item: $open) { f in PDFSheet(file: f).environment(\.layoutDirection, .rightToLeft) }
    }
}

// MARK: - My lessons, all of them

@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var lessons: [HistoryResponse.Lesson]?
    @Published var error: String?

    func load() async {
        if lessons == nil, let raw = LocalCache.read("history"), let c = try? API.decoder.decode(HistoryResponse.self, from: raw) { lessons = c.lessons }
        do {
            let raw = try await API.request("GET", "/api/native/student/history")
            lessons = try API.decoder.decode(HistoryResponse.self, from: raw).lessons
            LocalCache.write("history", raw)
            error = nil
        } catch APIError.notSignedIn {
            await AuthStore.shared.signOut()
        } catch {
            if lessons == nil { self.error = "לא הצלחנו לטעון את ההיסטוריה." }
        }
    }
}

/// Every lesson the student has had, in any group, including groups they have left, newest first, with what was covered and the PDFs.
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = HistoryModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("סגירה") { dismiss() }.buttonStyle(SoftButtonStyle(fg: .white, bg: Color.white.opacity(0.22)))
                Spacer()
                VStack(spacing: 0) {
                    Text("השיעורים שלי").font(.heebo(22, 900)).foregroundStyle(.white)
                    Text("כל מה שלמדתם, בכל קבוצה").font(.heebo(12, 700)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Color.clear.frame(width: 64, height: 1)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
            .background {
                Theme.hero.clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                    .shadow(color: Theme.brand700.opacity(0.25), radius: 10, y: 5).ignoresSafeArea(edges: .top)
            }
            ScrollView {
                VStack(spacing: 12) {
                    if let lessons = model.lessons {
                        if lessons.isEmpty {
                            EmptyState(pose: .sit, title: "עוד לא היו שיעורים", message: "אחרי השיעור הראשון תוכלו לראות כאן מה למדתם ולפתוח את הסיכומים של המורה.")
                        }
                        ForEach(lessons) { l in item(l) }
                    } else if let e = model.error {
                        Text(e).font(.heebo(14, 700)).foregroundStyle(Theme.rose600)
                    } else { ProgressView().padding(.top, 40) }
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .background(ScreenBackground())
        .task { await model.load() }
    }

    private func item(_ l: HistoryResponse.Lesson) -> some View {
        let tint = SubjectTint.of(l.groupTitle)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(l.groupTitle).font(.heebo(12, 900)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3).background(tint.gradient, in: Capsule())
                if !l.stillInGroup { Text("קבוצה שעזבתם").font(.heebo(11, 800)).foregroundStyle(Theme.slate600).padding(.horizontal, 8).padding(.vertical, 2).background(Theme.slate100, in: Capsule()) }
                Spacer(minLength: 4)
                if let a = l.attended { Pill(text: a ? "הייתי" : "לא הגעתי", icon: a ? "checkmark" : "xmark", fg: a ? Theme.emerald700 : Theme.rose600, bg: a ? Theme.emerald50 : Theme.rose50) }
            }
            Text(HebrewDate.lessonText(l.scheduledAt)).font(.heebo(17, 900)).foregroundStyle(Theme.ink)
            if let teacher = l.teacher { Text("עם \(teacher)").font(.heebo(13, 700)).foregroundStyle(Theme.slate500) }
            if let topics = l.topics, !topics.isEmpty { Text(topics).font(.heebo(14, 600)).foregroundStyle(Theme.slate700) }
            if let hw = l.homeworkText, !hw.isEmpty { Label(hw, systemImage: "pencil.and.list.clipboard").font(.heebo(13, 700)).foregroundStyle(Theme.orange700) }
            FileButtons(files: l.files)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
    }
}
