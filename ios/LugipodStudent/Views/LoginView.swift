import SwiftUI

/// Phone number, then the WhatsApp code. Email + password is the quiet fallback (also what the
/// App Review account uses). Same shape as the website's login: Lugi, the wordmark, one card.
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    private enum Step { case phone, code }
    @State private var step: Step = .phone
    @State private var phone = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var cooldown = 0
    @State private var submitted = ""
    @State private var showEmail = false
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    card
                        .frame(maxWidth: 460)
                        .padding(.horizontal, 20)
                    Spacer(minLength: 24)
                    Text("© 2026 לוגיפוד")
                        .font(.heebo(12, 500)).foregroundStyle(Theme.slate400)
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(ScreenBackground())
        .sheet(isPresented: $showEmail) {
            EmailLoginView().environment(\.layoutDirection, .rightToLeft)
        }
        .onAppear {
            #if DEBUG
            if PreviewMode.screen == "login-code" { step = .code; phone = "050-123-4567" }
            if PreviewMode.screen == "login-email" { showEmail = true }
            if PreviewMode.isOn { return }
            #endif
            focused = true
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Lugi(pose: .wave, height: 150).padding(.top, 4)
            Wordmark(size: 34).padding(.top, 2)
            Text("לתלמידים")
                .font(.heebo(13, 700)).foregroundStyle(Theme.brand700)
                .padding(.horizontal, 11).padding(.vertical, 3)
                .background(Theme.brand50, in: Capsule())
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(step == .phone ? "כניסה עם וואטסאפ" : "הקלידו את הקוד")
                    .font(.heebo(22, 800)).foregroundStyle(Theme.ink)
                Text(step == .phone
                     ? "נשלח קוד חד-פעמי לוואטסאפ שלכם."
                     : "שלחנו קוד בן 6 ספרות ל-\(Phone.format(phone)).")
                    .font(.heebo(15, 500)).foregroundStyle(Theme.slate500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)

            if let notice = auth.notice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(.heebo(13, 600)).foregroundStyle(Theme.amber800)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.amber50, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 14)
            }

            Group { if step == .phone { phoneStep } else { codeStep } }
                .padding(.top, 18)

            if let error {
                Text(error)
                    .font(.heebo(13, 600)).foregroundStyle(Theme.rose600)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }

            Button("כניסה עם אימייל במקום") { showEmail = true }
                .font(.heebo(14, 700)).foregroundStyle(Theme.slate600)
                .padding(.top, 20)
        }
        .card(padding: 28, radius: 32)
    }

    private var phoneStep: some View {
        VStack(spacing: 16) {
            LugiFieldBox(label: "מספר טלפון", focused: focused) {
                HStack(spacing: 10) {
                    // The country is always visible, so nobody wonders whether to type +972 (or can lose a digit to it).
                    HStack(spacing: 5) {
                        Text("🇮🇱").font(.system(size: 20))
                        Text("+972").font(.heebo(16, 800).monospacedDigit()).foregroundStyle(Theme.slate600)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    TextField("050-123-4567", text: $phone)
                        .keyboardType(.numberPad).textContentType(.telephoneNumber)
                        .font(.heebo(21, 600).monospacedDigit())
                        .environment(\.layoutDirection, .leftToRight)
                        .multilineTextAlignment(.leading)
                        .focused($focused)
                        .onChange(of: phone) { _, new in
                            let f = Phone.format(new)
                            if f != new { phone = f }
                        }
                }
            }
            Text(Phone.isValid(phone) ? "נשלח קוד בוואטסאפ למספר \(Phone.international(phone))" : "אפשר להקליד עם 0 או בלי, כמו שנוח")
                .font(.heebo(13, 600)).foregroundStyle(Phone.isValid(phone) ? Theme.emerald700 : Theme.slate500)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await sendCode() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text("שלחו לי קוד בוואטסאפ")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!Phone.isValid(phone) || busy)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 16) {
            OTPBoxes(code: $code, focused: $focused)
                .onChange(of: code) { _, new in
                    let d = String(new.filter(\.isNumber).prefix(6))
                    if d != new { code = d }
                    if d.count == 6 { Task { await verify() } }
                }
            Button { Task { await verify() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text("כניסה")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(code.count != 6 || busy)

            HStack(spacing: 22) {
                Button("מספר אחר") { step = .phone; code = ""; error = nil }
                Button(cooldown > 0 ? "שליחה חוזרת (\(cooldown))" : "שליחה חוזרת") { Task { await sendCode() } }
                    .disabled(cooldown > 0 || busy)
            }
            .font(.heebo(14, 700)).foregroundStyle(Theme.brand700)
        }
    }

    private func sendCode() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await auth.requestCode(phone: Phone.digits(phone))
            step = .code; code = ""; focused = true
            startCooldown()
        } catch { self.error = error.localizedDescription }
    }

    /// Checks the code once. A code is single-use, so the same six digits are never sent twice (a second tap or a re-typed code would fail
    /// with "expired" even though the first try got the person in), and if the server already signed this device in, that counts as success.
    private func verify() async {
        guard !busy, code.count == 6, code != submitted else { return }
        submitted = code
        busy = true; error = nil
        defer { busy = false }
        do { try await auth.verify(phone: phone, code: code) } catch {
            if await auth.adoptExistingSession() { return }
            self.error = AuthStore.otpMessage(for: error)
            code = ""; submitted = ""
        }
    }

    private func startCooldown() {
        cooldown = 45
        Task {
            while cooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                cooldown -= 1
            }
        }
    }
}

/// Six digit boxes driven by one hidden text field (so the keyboard's one-time-code suggestion works).
struct OTPBoxes: View {
    @Binding var code: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .focused(focused)
                .opacity(0.02)
                .accessibilityLabel("קוד אימות")
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let chars = Array(code)
                    let isActive = focused.wrappedValue && i == min(chars.count, 5)
                    Text(i < chars.count ? String(chars[i]) : "")
                        .font(.heebo(26, 700).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isActive ? Theme.brand500 : Theme.slate300, lineWidth: isActive ? 2 : 1)
                        )
                }
            }
            .allowsHitTesting(false)
        }
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}

struct EmailLoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var field: Field?
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Text("כניסה עם אימייל").font(.heebo(24, 800)).foregroundStyle(Theme.ink)
                        Spacer()
                        Button("סגירה") { dismiss() }.buttonStyle(SoftButtonStyle(fg: Theme.slate600, bg: Theme.slate100))
                    }
                    VStack(spacing: 16) {
                        LugiFieldBox(label: "אימייל", focused: field == .email) {
                            TextField("name@example.com", text: $email)
                                .keyboardType(.emailAddress).textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.heebo(17, 500))
                                .environment(\.layoutDirection, .leftToRight)
                                .focused($field, equals: .email)
                        }
                        LugiFieldBox(label: "סיסמה", focused: field == .password) {
                            SecureField("••••••••", text: $password)
                                .textContentType(.password)
                                .font(.heebo(17, 500))
                                .environment(\.layoutDirection, .leftToRight)
                                .focused($field, equals: .password)
                        }
                        if let error {
                            Text(error).font(.heebo(13, 600)).foregroundStyle(Theme.rose600)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button { Task { await submit() } } label: {
                            HStack(spacing: 8) {
                                if busy { ProgressView().tint(.white) }
                                Text("כניסה")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || email.isEmpty || password.isEmpty)
                    }
                    .card(padding: 24, radius: 28)
                }
                .frame(maxWidth: 460)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func submit() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            dismiss()
        } catch { self.error = "האימייל או הסיסמה שגויים." }
    }
}
