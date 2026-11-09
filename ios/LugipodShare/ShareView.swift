import SwiftUI

/// The screen after "Share → לוגיפוד": the picture, and where it goes: a Lugichat conversation (new or an existing one), or a question for a
/// teacher before a lesson (and which group). Hebrew, right to left, plain system fonts (an extension has little memory).
struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onClose: () -> Void
    let onDone: () -> Void

    private static let brand = Color(red: 0x4F / 255, green: 0x46 / 255, blue: 0xE5 / 255)
    private static let ink = Color(red: 0x0F / 255, green: 0x17 / 255, blue: 0x2A / 255)
    private static let soft = Color(red: 0x64 / 255, green: 0x74 / 255, blue: 0x8B / 255)
    private static let page = Color(red: 0xF6 / 255, green: 0xF7 / 255, blue: 0xFB / 255)

    var body: some View {
        VStack(spacing: 0) {
            header
            switch model.phase {
            case .loading: centered { ProgressView().controlSize(.large); Text("רגע…").foregroundStyle(Self.soft) }
            case .needsSignIn: signInNeeded
            case .done: success
            default: picker
            }
        }
        .background(Self.page)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var header: some View {
        HStack {
            Text("שליחה ללוגיפוד").font(.system(size: 18, weight: .heavy)).foregroundStyle(Self.ink)
            Spacer()
            if model.phase != .sending && model.phase != .done {
                Button("ביטול", action: onClose).foregroundStyle(Self.soft)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 14) { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity).padding(24).multilineTextAlignment(.center)
    }

    private var signInNeeded: some View {
        centered {
            Image(systemName: "person.crop.circle.badge.exclamationmark").font(.system(size: 44)).foregroundStyle(Self.brand)
            Text("צריך להתחבר פעם אחת").font(.system(size: 20, weight: .heavy)).foregroundStyle(Self.ink)
            Text("פתחו את האפליקציה \"לוגיפוד\" והתחברו, ואז שתפו שוב את התמונה.").foregroundStyle(Self.soft)
            Button("סגירה", action: onClose).buttonStyle(.bordered)
        }
    }

    private var success: some View {
        centered {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
            switch model.sentTo {
            case .group:
                Text("השאלה נשלחה למורה").font(.system(size: 22, weight: .heavy)).foregroundStyle(Self.ink)
                Text("המורה יראה אותה לפני השיעור.").foregroundStyle(Self.soft)
            default:
                Text("התמונה נשמרה בשיחה").font(.system(size: 22, weight: .heavy)).foregroundStyle(Self.ink)
                Text("פתחו את לוגיפוד: השיחה מחכה לכם שם, ולוגיפוקס יענה.").foregroundStyle(Self.soft)
            }
            Button("סיום", action: onDone).buttonStyle(.borderedProminent).tint(Self.brand).controlSize(.large)
        }
    }

    private var picker: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Image(uiImage: model.image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 150).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    TextField("הוסיפו הערה או שאלה (לא חובה)", text: $model.note, axis: .vertical)
                        .lineLimit(1...3).padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    sectionTitle("לאן לשלוח?")
                    Text("לוגיצ׳אט").font(.system(size: 13, weight: .heavy)).foregroundStyle(Self.soft)
                    row(.newChat, icon: "plus.bubble.fill", title: "שיחה חדשה עם לוגיפוקס", subtitle: nil)
                    ForEach(model.chats) { chat in
                        row(.chat(chat.id), icon: chat.hasImage ? "photo.fill" : "bubble.left.fill", title: chat.title, subtitle: chat.snippet.isEmpty ? nil : chat.snippet)
                    }
                    if !model.groups.isEmpty {
                        Text("שאלה למורה לפני שיעור").font(.system(size: 13, weight: .heavy)).foregroundStyle(Self.soft).padding(.top, 8)
                        ForEach(model.groups) { group in
                            row(.group(group.id), icon: "graduationcap.fill", title: groupTitle(group), subtitle: lessonLine(group))
                        }
                    }
                }
                .frame(maxWidth: 560).padding(.horizontal, 18).padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
            footer
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 17, weight: .heavy)).foregroundStyle(Self.ink).padding(.top, 6)
    }

    private func groupTitle(_ g: ShareGroup) -> String {
        [g.subject, g.teacher].compactMap { $0 }.joined(separator: " · ")
    }

    private func lessonLine(_ g: ShareGroup) -> String? {
        guard let lesson = g.lesson else { return "אין שיעור קרוב" }
        if lesson.live { return "השיעור מתקיים עכשיו" }
        return "השיעור הבא: " + lesson.startsAt.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "he_IL")))
    }

    private func row(_ value: ShareChoice, icon: String, title: String, subtitle: String?) -> some View {
        let on = model.choice == value
        return Button { model.choice = value } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Self.brand : Self.soft.opacity(0.6)).font(.system(size: 22))
                Image(systemName: icon).foregroundStyle(Self.brand).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Self.ink).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Self.soft).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(on ? Self.brand.opacity(0.08) : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Self.brand : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .sending)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if case .failed(let message) = model.phase {
                Text(message).font(.system(size: 14, weight: .bold)).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button {
                Task { await model.send() }
            } label: {
                if model.phase == .sending {
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("שולחים…") }.frame(maxWidth: .infinity)
                } else {
                    Text(sendTitle).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent).tint(Self.brand).controlSize(.large)
            .disabled(model.phase == .sending)
            .frame(maxWidth: 560)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var sendTitle: String {
        switch model.choice {
        case .newChat: return "שליחה לשיחה חדשה"
        case .chat: return "הוספה לשיחה"
        case .group: return "שליחה למורה"
        }
    }
}
