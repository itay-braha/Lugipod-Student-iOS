import SwiftUI
import UIKit

/// How to send a picture to לוגיפוד from another app. iOS does not switch a new share option on by itself: it is found once under "More"
/// in the share sheet and turned on, after which it stays in the row.
struct ShareHowToSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("1", "פתחו תמונה בוואטסאפ, בגלריה או בכל אפליקציה, ולחצו על כפתור השיתוף (הריבוע עם החץ)."),
        ("2", "בשורת האפליקציות, גללו עד הסוף ולחצו על \"עוד\"."),
        ("3", "הפעילו את \"לוגיפוד\" (המתג) ולחצו על \"סיום\". זה נעשה פעם אחת בלבד."),
        ("4", "מעכשיו \"לוגיפוד\" מופיע בשיתוף. בחרו לאן התמונה הולכת: שיחה עם לוגיפוקס או שאלה למורה."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Lugi(pose: .phone, height: 150, breathing: true).padding(.top, 8)
                    Text("שולחים תמונה ללוגיפוד מכל אפליקציה").font(.heebo(22, 900)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(steps, id: \.0) { step in
                            HStack(alignment: .top, spacing: 12) {
                                Text(step.0).font(.heebo(15, 900)).foregroundStyle(.white)
                                    .frame(width: 28, height: 28).background(Theme.brand600, in: Circle())
                                Text(step.1).font(.heebo(15, 600)).foregroundStyle(Theme.slate700).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .card(padding: 16, radius: 20)
                    Text("השיחות נשמרות בלוגיצ׳אט, כולל התמונות, ואפשר לחזור אליהן.").font(.heebo(14, 600)).foregroundStyle(Theme.slate600).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 560).padding(20).frame(maxWidth: .infinity)
            }
            .background(ScreenBackground())
            .navigationTitle("שיתוף תמונות")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("סגירה") { dismiss() } } }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
