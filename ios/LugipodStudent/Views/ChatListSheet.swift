import SwiftUI

/// "My conversations": the student's saved Lugichat conversations (the newest 15), open one, delete one, or start a new one. A conversation
/// that began with a shared picture shows a picture mark; opening it shows the picture again.
struct ChatListSheet: View {
    @EnvironmentObject private var model: LugichatModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.chats.isEmpty {
                    EmptyState(pose: .search, title: "עדיין אין שיחות שמורות", message: "כל שיחה עם לוגיפוקס נשמרת כאן, כולל התמונות, ואפשר לחזור אליה.")
                } else {
                    List {
                        ForEach(model.chats) { chat in
                            Button {
                                Task { await model.open(chatId: chat.id); dismiss() }
                            } label: { row(chat) }
                            .listRowBackground(model.chatId == chat.id ? Theme.violet50 : Color.white)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { model.chats[$0].id }
                            Task { for id in ids { await model.deleteChat(id) } }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ScreenBackground())
            .navigationTitle("השיחות שלי")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("סגירה") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.reset(); dismiss() } label: { Label("שיחה חדשה", systemImage: "square.and.pencil") }
                }
            }
        }
        .task { await model.refreshChats() }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func row(_ chat: ChatSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: chat.hasImage ? "photo.fill" : "bubble.left.fill")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(chat.hasImage ? Theme.orange500 : Theme.violet500)
                .frame(width: 38, height: 38)
                .background((chat.hasImage ? Theme.orange100 : Theme.violet50), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(chat.title).font(.heebo(16, 800)).foregroundStyle(Theme.ink).lineLimit(1)
                if !chat.snippet.isEmpty {
                    Text(chat.snippet).font(.heebo(13, 500)).foregroundStyle(Theme.slate600).lineLimit(1)
                }
                Text(chat.lastAt, style: .relative).font(.heebo(12, 600)).foregroundStyle(Theme.slate400)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
