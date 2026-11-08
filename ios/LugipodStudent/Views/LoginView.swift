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
                PhoneField(phone: $phone, focused: $focused)
            }
            if Phone.isValid(phone) {
                Text("נשלח קוד בוואטסאפ למספר \(Phone.international(phone))")
                    .font(.heebo(13, 600)).foregroundStyle(Theme.emerald700)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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

/// The phone number box, drawn by us: the Israeli flag and +972 on the left, then the number as a template that fills in as you type
/// ("05•-•••-••••": the 05 is already there in grey, dashes appear by themselves, each digit you press turns solid ink).
/// The keyboard talks to an invisible text field; what the person sees is plain system-font `Text` in solid colours with our own caret,
/// so what they type can never turn out invisible (the way the code boxes below already work).
struct PhoneField: View {
    @Binding var phone: String
    var focused: FocusState<Bool>.Binding

    private static let ink = Color(red: 0.06, green: 0.09, blue: 0.16)
    private var digitFont: Font { .system(size: 25, weight: .medium).monospacedDigit() }

    var body: some View {
        let typed = Phone.national(phone)
        ZStack(alignment: .leading) {
            TextField("", text: $phone)
                .keyboardType(.numberPad).textContentType(.telephoneNumber)
                .focused(focused)
                .opacity(0.02)
                .frame(maxWidth: .infinity, minHeight: 56)
                .accessibilityIdentifier("phone-input")
                .accessibilityLabel("מספר טלפון")
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Text("🇮🇱").font(.system(size: 26))
                    Text("+972").font(.system(size: 21, weight: .medium).monospacedDigit()).foregroundStyle(Self.ink)
                }
                Rectangle().fill(Theme.slate200).frame(width: 1, height: 30)
                HStack(spacing: 1) {
                    if !typed.isEmpty {
                        Text(typed).font(digitFont).foregroundStyle(Self.ink)
                            .accessibilityIdentifier("phone-display")
                    }
                    if focused.wrappedValue { Caret() }
                    if typed.isEmpty { Text("50-123-4567").font(digitFont).foregroundStyle(Theme.slate300) }   // the usual light placeholder, gone with the first digit
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
        }
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
        // Only the nine digits after +972 are typed, the first is always 5 (`Phone.sanitizeTyped`). Ordinary typing is never rewritten under the
        // keyboard (that lost keystrokes); a refused key (a 0 or another first digit), extra digits and a paste are the only things tidied.
        .onChange(of: phone) { old, new in
            let s = Phone.sanitizeTyped(old: old, new: new)
            if s != new { phone = s }
        }
    }
}

/// A blinking text cursor for the boxes we draw ourselves.
struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Rectangle()
                .fill(Theme.brand500)
                .frame(width: 2, height: 26)
                .opacity(Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
        }
        .accessibilityHidden(true)
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
                                .accessibilityIdentifier("email-input")
                                .font(.heebo(17, 500))
                                .foregroundStyle(Theme.ink)
                                .environment(\.layoutDirection, .leftToRight)
                                .focused($field, equals: .email)
                        }
                        LugiFieldBox(label: "סיסמה", focused: field == .password) {
                            SecureField("••••••••", text: $password)
                                .textContentType(.password)
                                .accessibilityIdentifier("password-input")
                                .font(.heebo(17, 500))
                                .foregroundStyle(Theme.ink)
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
