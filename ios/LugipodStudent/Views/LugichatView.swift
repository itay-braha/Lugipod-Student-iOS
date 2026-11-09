import PhotosUI
import SwiftUI

/// Lugichat: a chat. Type, or attach a photo of the question, and Lugi answers step by step. No subject to choose, no fox in the way.
struct LugichatView: View {
    @EnvironmentObject private var home: HomeModel
    @EnvironmentObject private var model: LugichatModel
    @State private var draft = ""
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var typing = false
    @State private var showChats = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if model.hasThread { thread } else { welcome }
            composer
        }
        .background(ScreenBackground())
        .sheet(isPresented: $showChats) { ChatListSheet().environmentObject(model) }
        .overlay { if model.opening { ProgressView().controlSize(.large).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { model.pending = $0 }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { model.pending = img }
                pickerItem = nil
            }
        }
        .onAppear {
            #if DEBUG
            if let preview = PreviewMode.lugichat(), !model.hasThread { model.loadPreview(preview) }
            #endif
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image("Lugi-walk").resizable().scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
                Text("לוגיצ׳אט").font(.heebo(22, 900)).foregroundStyle(.white)
            }
            Spacer()
            Button { showChats = true } label: {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.violet700)
                    .frame(width: 42, height: 42).background(Color.white, in: Circle())
            }
            .accessibilityLabel("השיחות שלי")
            if model.hasThread {
                Button { model.reset(); draft = "" } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.violet700)
                        .frame(width: 42, height: 42).background(Color.white, in: Circle())
                }
                .accessibilityLabel("שיחה חדשה")
            }
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Theme.violet700, Theme.brand600, Theme.brand500], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous))
                .shadow(color: Theme.violet700.opacity(0.3), radius: 10, y: 5)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Empty state

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            // The fox is who they are asking.
            Lugi(pose: [.study, .wave, .search, .wink, .ponder, .sit][model.greetingSeed % 6], height: 150)
            Text(model.greeting(name: home.data?.student.name ?? ""))
                .font(.heebo(30, 800)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text("כתבו שאלה, או צלמו תרגיל. אני מדריך צעד אחר צעד.")
                .font(.heebo(16, 500)).foregroundStyle(Theme.slate500).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                if cameraAvailable { suggestion("צילום של תרגיל שתקוע", icon: "camera.fill", color: Theme.orange500) { showCamera = true } }
                suggestion("הסבירו לי נושא", icon: "lightbulb.fill", color: Theme.brand600) { draft = "תסבירו לי "; typing = true }
                suggestion("בדקו לי את הפתרון", icon: "checkmark.seal.fill", color: Theme.emerald600) { draft = "בדקו לי את הפתרון: "; typing = true }
            }
            .frame(maxWidth: 420)
            .padding(.top, 8)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { typing = false }
    }

    private func suggestion(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(color.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title).font(.heebo(16, 800)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).foregroundStyle(color)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(color.opacity(0.45), lineWidth: 1.5))
            .shadow(color: color.opacity(0.18), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: Conversation

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(model.messages) { m in row(m).id(m.id) }
                    if model.sending {
                        HStack(spacing: 10) { Lugi(pose: .ponder, height: 52); TypingDots() }.frame(maxWidth: .infinity, alignment: .leading).id("typing")
                    }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.heebo(14, 600)).foregroundStyle(Theme.rose600)
                            if model.canRetry { Button("נסו שוב") { Task { await model.retry() } }.buttonStyle(SoftButtonStyle()) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let low = model.runningLow, !model.sending, model.messages.last?.role == .bot {
                        Text(low == 1 ? "נשארה לך תשובה אחת להיום" : "נשארו לך \(low) תשובות להיום")
                            .font(.heebo(12, 600)).foregroundStyle(Theme.slate400).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if model.limitHit { limitCard }
                    Color.clear.frame(height: 2).id("end")
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 18).padding(.top, 6)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            // A saved conversation opens at its latest message, not at the top (the first scroll waits for the thread to be laid out).
            .task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                proxy.scrollTo("end")
            }
            .onChange(of: model.messages) { _, _ in withAnimation { proxy.scrollTo("end") } }
            .onChange(of: model.sending) { _, _ in withAnimation { proxy.scrollTo("end") } }
            .onChange(of: model.limitHit) { _, _ in withAnimation { proxy.scrollTo("end") } }
        }
    }

    @ViewBuilder
    private func row(_ m: ChatMessage) -> some View {
        switch m.role {
        case .student:
            VStack(alignment: .leading, spacing: 8) {
                if let image = m.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 190, height: 150).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .tapToZoom(image)
                }
                if !m.body.isEmpty {
                    Text(m.body).font(.heebo(16, 600)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.brand600, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 40)
        case .bot:
            // Lugi answers: his face beside the text, no bubble around it.
            HStack(alignment: .top, spacing: 10) {
                FoxAvatar()
                // While the answer is still being written it is plain text: the formula view would reload its whole page for every
                // new word. The finished answer is typeset once.
                if m.id == model.streamingId {
                    Text(RichText.attributed(m.body)).font(.heebo(16, 500)).foregroundStyle(Theme.ink)
                        .lineSpacing(4).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    RichText(text: m.body, font: .heebo(16, 500), color: Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shown only when the free allowance is really over: the free answers renew tomorrow, and going on now costs lugis, said plainly BEFORE
    /// anything is used, so the next answer is never a surprise. The lugis count in the student's usage and appear on the family's monthly bill.
    private var limitCard: some View {
        let lugis = model.quota?.packLugis ?? 2
        let size = model.quota?.packSize ?? 120
        let days = model.quota?.packDays ?? 14
        let lugisText = lugis == lugis.rounded() ? String(Int(lugis)) : String(format: "%.1f", lugis)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Lugi(pose: .nap, height: 58)
                Text("עד כאן להיום בלי עלות").font(.heebo(18, 800)).foregroundStyle(Theme.ink)
            }
            Text("כל תשובה של לוגיפוקס היא עבודה אמיתית של מודל חכם, ולכן התשובות החינמיות מוגבלות ביום. מחר בבוקר הן מתחדשות.")
                .font(.heebo(14, 500)).foregroundStyle(Theme.slate600)
            VStack(alignment: .leading, spacing: 4) {
                Text("רוצים להמשיך עכשיו?").font(.heebo(15, 800)).foregroundStyle(Theme.ink)
                Text("\(size) תשובות נוספות, בתוקף \(days) ימים, ב־\(lugisText) לוגי. הלוגי נספרים בצריכה שלכם החודש.")
                    .font(.heebo(14, 600)).foregroundStyle(Theme.slate700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            switch model.pack {
            case .parentTold:
                Label("שלחנו להורה הודעה עם כל הפרטים ✓", systemImage: "checkmark.circle.fill")
                    .font(.heebo(14, 800)).foregroundStyle(Theme.emerald700)
            case .capReached:
                Text("הגעתם למגבלה החודשית, ולכן אי אפשר להמשיך כרגע.").font(.heebo(13, 700)).foregroundStyle(Theme.rose600)
                Button { Task { await model.tellParent() } } label: { Label("עדכנו את ההורה", systemImage: "paperplane.fill") }
                    .buttonStyle(CTAButtonStyle())
            default:
                if case .failed(let message) = model.pack { Text(message).font(.heebo(13, 700)).foregroundStyle(Theme.rose600) }
                Button { Task { await model.buyPack() } } label: {
                    HStack(spacing: 8) {
                        if model.pack == .buying { ProgressView().tint(.white) }
                        Text("המשך עכשיו · \(lugisText) לוגי")
                    }
                }
                .buttonStyle(CTAButtonStyle())
                .disabled(model.pack == .buying)
                .accessibilityIdentifier("lugichat-continue")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(colors: [Theme.violet50, Color.white], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.violet500.opacity(0.25), lineWidth: 1))
    }

    // MARK: Composer

    @ViewBuilder private var composer: some View {
        if model.limitHit {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let img = model.pending {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .tapToZoom(img)
                        Button { model.pending = nil } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.white, Theme.slate700)
                        }
                        .offset(x: -6, y: -6)
                        .accessibilityLabel("הסרת התמונה")
                    }
                    .padding(.top, 6)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    if cameraAvailable {
                        Button { showCamera = true } label: { attach("camera.fill") }.accessibilityLabel("צילום")
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) { attach("photo.fill") }.accessibilityLabel("תמונה מהגלריה")
                    ZStack(alignment: .leading) {
                        if draft.isEmpty {
                            Text("שאלו את לוגיפוקס…").font(.heebo(16, 500)).foregroundStyle(Theme.slate400)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        // Also takes a pasted picture (from WhatsApp, Photos...): it becomes the attached image, like in Messages.
                        PasteAwareTextView(text: $draft, focused: $typing) { image in
                            model.pending = image
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                    Button { submit() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(canSend ? AnyShapeStyle(LinearGradient(colors: [Theme.violet500, Theme.brand600], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.slate300), in: Circle())
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("שליחה")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.slate200, lineWidth: 1))
            .shadow(color: Theme.shadowSoft2, radius: 8, y: 3)
            .frame(maxWidth: 720)
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
        }
    }

    private func attach(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.violet700)
            .frame(width: 40, height: 40).background(Theme.violet50, in: Circle())
    }

    private var canSend: Bool {
        !model.sending && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.pending != nil)
    }

    private func submit() {
        let text = draft
        draft = ""
        Task { await model.send(text) }
    }
}

/// Lugi's face, the small round avatar that sits next to everything he says.
struct FoxAvatar: View {
    var size: CGFloat = 38
    var body: some View {
        Image("Lugi-peek").resizable().scaledToFill()
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(hex: 0xFFEDD5), Color(hex: 0xFED7AA)], startPoint: .top, endPoint: .bottom), in: Circle())
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.orange300, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// Three dots that pulse while Lugi is thinking.
struct TypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Theme.violet500.opacity(phase == i ? 1 : 0.3)).frame(width: 9, height: 9)
            }
        }
        .padding(.vertical, 8)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .accessibilityLabel("לוגיפוקס חושב")
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
