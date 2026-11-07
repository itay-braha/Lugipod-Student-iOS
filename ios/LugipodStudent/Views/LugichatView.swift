import PhotosUI
import SwiftUI

/// The camera screen of Lugichat: photograph a question, then talk it through with Lugi step by step.
struct LugichatView: View {
    @EnvironmentObject private var home: HomeModel
    @StateObject private var model = LugichatModel()
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var draft = ""
    @FocusState private var typing: Bool

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var quota: Quota? { model.quota ?? home.data?.lugichat }
    private var subjects: [StudentHome.Subject] { home.data?.subjects ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.hasThread { thread } else { intro }
            if model.hasThread && !model.limitHit { composer }
        }
        .background(ScreenBackground())
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { model.start(with: $0) }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    model.start(with: img)
                }
                pickerItem = nil
            }
        }
        .onAppear {
            #if DEBUG
            if let preview = PreviewMode.lugichat() { model.loadPreview(preview) }
            #endif
            if model.subjectId == nil { model.subjectId = subjects.first(where: \.mine)?.id ?? subjects.first?.id }
        }
        .onChange(of: subjects) { _, list in
            if model.subjectId == nil { model.subjectId = list.first(where: \.mine)?.id ?? list.first?.id }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("לוגיצ׳אט").font(.heebo(26, 800)).foregroundStyle(Theme.ink)
                Text(allowanceLine).font(.heebo(13, 600)).foregroundStyle(Theme.slate500)
            }
            Spacer()
            if model.hasThread {
                Button("שאלה חדשה") { model.reset(); draft = "" }.buttonStyle(SoftButtonStyle())
            }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
    }

    private var allowanceLine: String {
        guard let q = quota, let left = q.freeLeft else { return "צלמו שאלה ולוגי ידריך אתכם" }
        let total = left + (q.packLeft ?? 0)
        return total > 0 ? "נשארו \(total) תשובות להיום" : "התשובות של היום נגמרו"
    }

    // MARK: Before a photo

    private var intro: some View {
        ScrollView {
            VStack(spacing: 18) {
                Lugi(pose: .study, height: 150).padding(.top, 8)
                Text("צלמו שאלה שתקעה אתכם").font(.heebo(22, 800)).foregroundStyle(Theme.ink)
                Text("לוגי לא נותן את התשובה מיד. הוא מדריך אתכם צעד אחר צעד, ואפשר תמיד לבקש רמז או פתרון.")
                    .font(.heebo(15, 500)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                if subjects.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(subjects) { s in
                                Button { model.subjectId = s.id } label: {
                                    Text(s.name).font(.heebo(14, 700))
                                        .foregroundStyle(model.subjectId == s.id ? .white : Theme.slate600)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(model.subjectId == s.id ? Theme.brand600 : Color.white, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Theme.slate200, lineWidth: model.subjectId == s.id ? 0 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                VStack(spacing: 12) {
                    if cameraAvailable {
                        Button { showCamera = true } label: { Label("צילום שאלה", systemImage: "camera.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("בחירה מהגלריה", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(cameraAvailable ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
                }
                .padding(.horizontal, 20)

                if quota?.canAsk == false {
                    limitCard.padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 30)
        }
    }

    // MARK: Conversation

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if let image = model.image {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.messages) { m in bubble(m).id(m.id) }
                    if model.sending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("לוגי חושב…").font(.heebo(14, 600)).foregroundStyle(Theme.slate500)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).id("typing")
                    }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.heebo(14, 600)).foregroundStyle(Theme.rose600)
                            if model.canRetry {
                                Button("נסו שוב") { Task { await model.send(nil) } }.buttonStyle(SoftButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if model.limitHit { limitCard }
                    Color.clear.frame(height: 4).id("end")
                }
                .padding(.horizontal, 16).padding(.top, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages) { _, _ in withAnimation { proxy.scrollTo("end") } }
            .onChange(of: model.sending) { _, _ in withAnimation { proxy.scrollTo("end") } }
        }
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case .student:
            Text(m.body)
                .font(.heebo(16, 600)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.brand600, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        case .bot:
            HStack(alignment: .top, spacing: 8) {
                Image("Lugi-peek").resizable().scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true)
                MathText(text: m.body)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 24)
        }
    }

    private var limitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("התשובות של היום נגמרו").font(.heebo(17, 800)).foregroundStyle(Theme.amber800)
            Text("מחר בבוקר מתחדשות התשובות החינמיות. בינתיים אפשר לתרגל באתגר היומי או לשאול את המורה בשיעור.")
                .font(.heebo(14, 500)).foregroundStyle(Theme.amber800)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, fill: Theme.amber50, border: Theme.amber200)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if !model.sending && model.messages.last?.role == .bot {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        quick("רמז נוסף", "אפשר רמז נוסף?")
                        quick("לא הבנתי", "לא הבנתי, אפשר להסביר אחרת?")
                        quick("הראו לי פתרון", "אני תקוע/ה. אפשר לראות את הפתרון המלא?")
                    }
                    .padding(.horizontal, 16)
                }
            }
            HStack(spacing: 10) {
                TextField("כתבו תשובה או שאלה…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.heebo(16, 500))
                    .focused($typing)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.slate300, lineWidth: 1))
                Button {
                    let text = draft
                    draft = ""
                    Task { await model.send(text) }
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(canSend ? Theme.brand600 : Theme.brand300, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("שליחה")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8).padding(.bottom, 8)
        .background(Theme.page.opacity(0.96))
    }

    private var canSend: Bool {
        !model.sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func quick(_ label: String, _ text: String) -> some View {
        Button { Task { await model.send(text) } } label: {
            Text(label).font(.heebo(14, 700)).foregroundStyle(Theme.brand700)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.brand50, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.brand200, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Type-erased button style, so one `.buttonStyle` call can pick between two styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// The system camera, full screen.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
