import XCTest
@testable import LugipodStudent

@MainActor
final class AppLogicTests: XCTestCase {
    func testPhoneFormatting() {
        XCTAssertEqual(Phone.format("0501234567"), "050-123-4567")
        XCTAssertTrue(Phone.isValid("050-123-4567"))
        XCTAssertFalse(Phone.isValid("0412345678"))
        XCTAssertEqual(Phone.e164("050-123-4567"), "+972501234567")
    }

    func testRouterDestinations() {
        XCTAssertEqual(AppRouter.destination(for: "/home"), .tab(.home))
        XCTAssertEqual(AppRouter.destination(for: "/alerts"), .alerts)
        XCTAssertEqual(AppRouter.destination(for: "/lugichat"), .tab(.lugichat))
        XCTAssertEqual(AppRouter.destination(for: "/meeting/lesson/abc"), .web("/meeting/lesson/abc"))
        XCTAssertEqual(AppRouter.destination(for: "//evil.example"), .tab(.home))
    }

    func testHomeDecodesGroupsWithEverythingTheCardShows() throws {
        let data = PreviewMode.response(method: "GET", path: "/api/native/student/home")
        let home = try API.decoder.decode(StudentHome.self, from: data)
        XCTAssertEqual(home.groups.count, 4)
        let math = try XCTUnwrap(home.groups.first)
        XCTAssertEqual(math.teacher, "איתי")
        XCTAssertEqual(math.mates.count, 3)
        XCTAssertEqual(math.homework.first?.isDone, false)
        XCTAssertEqual(math.myQuestions, 1)
        XCTAssertEqual(home.groups[1].homework.first?.isDone, true)
        XCTAssertEqual(home.consumption.capLugis, 12)
        XCTAssertFalse(home.family.hasParent)
        XCTAssertEqual(home.lugichat?.freeLeft, 14)
        XCTAssertEqual(home.dailyChallenge.streak, 6)
    }

    func testLessonPhaseIsComputedOnTheDevice() throws {
        let home = try API.decoder.decode(StudentHome.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/home"))
        let live = try XCTUnwrap(home.groups.first?.upcoming.first)
        XCTAssertEqual(live.phase(), .live)                                                       // started five minutes ago
        XCTAssertEqual(live.phase(now: live.scheduledAt.addingTimeInterval(-20 * 60)), .upcoming) // 20 minutes before
        XCTAssertEqual(live.phase(now: live.scheduledAt.addingTimeInterval(-10 * 60)), .live)     // joinable from 15 minutes before
        XCTAssertEqual(live.phase(now: live.scheduledAt.addingTimeInterval(3 * 3600)), .ended)
    }

    func testGroupDetailDecodes() throws {
        let detail = try API.decoder.decode(GroupDetail.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/group/g1"))
        XCTAssertEqual(detail.past.count, 3)
        XCTAssertEqual(detail.past.last?.attended, false)
        XCTAssertEqual(detail.upcoming.count, 3)
        XCTAssertEqual(detail.questions.count, 1)
    }

    func testQuotaOnlyWarnsWhenLow() throws {
        let q = try API.decoder.decode(Quota.self, from: Data("{\"free_left\":3,\"pack_left\":0}".utf8))
        XCTAssertEqual(q.remaining, 3)
        XCTAssertNil(try API.decoder.decode(Quota.self, from: Data("{}".utf8)).remaining)
        let model = LugichatModel()
        XCTAssertNil(model.runningLow)                    // nothing known yet: say nothing
    }

    func testGreetingChangesWithTheSeedAndNeverMentionsLimits() {
        let model = LugichatModel()
        let line = model.greeting(name: "נועה כהן")
        XCTAssertFalse(line.isEmpty)
        XCTAssertFalse(line.contains("20"))
        XCTAssertFalse(line.contains("תשובות"))
    }

    func testMathPageEscapesAndKeepsFormulas() {
        let page = MathHTML.page("<b>x</b> & **bold** $a<b$\nשורה")
        XCTAssertTrue(page.contains("&lt;b&gt;x&lt;/b&gt; &amp; <b>bold</b> $a&lt;b$<br>שורה"))
    }

    func testPhotoIsShrunkAndEncoded() {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let b64 = LugichatModel.encode(big)
        let data = Data(base64Encoded: b64)
        XCTAssertNotNil(data)
        let decoded = UIImage(data: data ?? Data())
        XCTAssertEqual(max(decoded?.size.width ?? 0, decoded?.size.height ?? 0), 1600)
        XCTAssertLessThan(b64.count, 6_000_000)
    }

    func testDailyPayloadCarriesAnswersForInstantFeedback() throws {
        let daily = try API.decoder.decode(DailyPayload.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/daily"))
        XCTAssertEqual(daily.questions.count, 2)
        XCTAssertEqual(daily.questions.first?.choices.count, 4)
        XCTAssertEqual(daily.questions.first?.answerIndex, 1)
        XCTAssertEqual(daily.subject?.name, "פיזיקה")
    }

    func testDailyModelAnswersInstantly() throws {
        let model = DailyModel()
        model.apply(try API.decoder.decode(DailyPayload.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/daily")))
        XCTAssertEqual(model.phase, .ready)
        let q = try XCTUnwrap(model.question)
        model.pick(q.answerIndex)                                // no await: the result is there at once
        XCTAssertEqual(model.result?.correct, true)
        XCTAssertEqual(model.correctCount, 1)
        model.next()
        let q2 = try XCTUnwrap(model.question)
        model.pick((q2.answerIndex + 1) % q2.choices.count)
        XCTAssertEqual(model.result?.correct, false)
        model.next()
        XCTAssertEqual(model.phase, .finished)
    }

    func testFriendsProfileHistoryDecode() throws {
        let f = try API.decoder.decode(FriendsResponse.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/friends"))
        XCTAssertEqual(f.friends.count, 2)
        XCTAssertEqual(f.groups.first?.members.count, 3)
        XCTAssertEqual(f.groups.first?.members.first?.isFriend, true)
        XCTAssertEqual(f.incoming.first?.from.name, "איתן")
        XCTAssertEqual(f.me?.highestStreak, 14)
        let p = try API.decoder.decode(ProfileResponse.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/profile"))
        XCTAssertEqual(p.items.filter(\.unlocked).count, 4)
        XCTAssertEqual(p.items.first { !$0.unlocked }?.hint, "עוד 360 נקודות")
        let h = try API.decoder.decode(HistoryResponse.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/history"))
        XCTAssertEqual(h.lessons.count, 2)
        XCTAssertEqual(h.lessons[0].files.first?.name, "סיכום-שיעור-6.pdf")
        XCTAssertFalse(h.lessons[1].stillInGroup)
        let detail = try API.decoder.decode(GroupDetail.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/group/g1"))
        XCTAssertEqual(detail.past.first?.files?.count, 1)
        let home = try API.decoder.decode(StudentHome.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/home"))
        XCTAssertEqual(home.dailyChallenge.toGift, 4)
    }

    func testFoxPosesRotate() {
        let center = CelebrationCenter()
        var seen = Set<LugiPose>()
        for _ in 0..<5 { center.fox("x"); if let p = center.fox?.pose { seen.insert(p) } }
        XCTAssertGreaterThanOrEqual(seen.count, 4)          // the same fox does not greet every right answer
    }

    func testPhoneIsNormalisedWhateverIsTyped() {
        for typed in ["0501234567", "501234567", "050-123-4567", "+972 50-123-4567", "972501234567", "00972501234567", "٠٥٠١٢٣٤٥٦٧"] {
            XCTAssertEqual(Phone.digits(typed), "0501234567", typed)
            XCTAssertTrue(Phone.isValid(typed), typed)
            XCTAssertEqual(Phone.e164(typed), "+972501234567", typed)
        }
        XCTAssertEqual(Phone.format("5"), "05")                      // typing 5 first shows 05, nothing is lost
        XCTAssertEqual(Phone.format("0501"), "050-1")
        XCTAssertEqual(Phone.international("0501234567"), "+972 50-123-4567")
        XCTAssertFalse(Phone.isValid("0412345678"))
        XCTAssertFalse(Phone.isValid("05012345"))
    }

    func testPhoneBoxTakesNineDigitsStartingWithFive() {
        XCTAssertEqual(Phone.national("501234567"), "50-123-4567")
        XCTAssertEqual(Phone.national("5"), "5")
        XCTAssertEqual(Phone.national("5012"), "50-12")
        XCTAssertEqual(Phone.national(""), "")
        // typing: 0 and other first digits are refused, extra digits ignored
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "0"), "")
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "3"), "")
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "05"), "5")
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "5"), "5")
        XCTAssertEqual(Phone.sanitizeTyped(old: "50", new: "501"), "501")
        XCTAssertEqual(Phone.sanitizeTyped(old: "5012", new: "501234"), "501234")          // two keystrokes in one change are normal typing
        XCTAssertEqual(Phone.sanitizeTyped(old: "501234567", new: "5012345679"), "501234567")
        // paste / auto-fill, however it is written
        for pasted in ["0501234567", "501234567", "050-123-4567", "+972 50-123-4567", "972501234567", "00972501234567", "٠٥٠١٢٣٤٥٦٧"] {
            XCTAssertEqual(Phone.sanitizeTyped(old: "", new: pasted), "501234567", pasted)
        }
        XCTAssertEqual(Phone.sanitizeTyped(old: "", new: "0412345678"), "")                 // a landline is not accepted
        XCTAssertTrue(Phone.isValid("501234567"))
        XCTAssertEqual(Phone.e164("501234567"), "+972501234567")
    }

    func testOtpMessagesDistinguishWrongCodeFromNoConnection() {
        XCTAssertTrue(AuthStore.otpMessage(for: URLError(.notConnectedToInternet)).contains("אין חיבור"))
        struct E: Error, CustomStringConvertible { let description: String }
        XCTAssertTrue(AuthStore.otpMessage(for: E(description: "token has expired or is invalid")).contains("הקוד לא התקבל"))
    }

    func testGiftLugisAreDecodedAndGoneAtZero() throws {
        let home = try API.decoder.decode(StudentHome.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/home"))
        XCTAssertEqual(home.consumption.giftLugis, 5)
        let none = #"{"consumedLugis":3,"capLugis":null,"pctUsed":0,"uncapped":true}"#
        let c = try API.decoder.decode(StudentHome.Consumption.self, from: Data(none.utf8))
        XCTAssertNil(c.giftLugis)                           // an older server, or no gift: nothing is shown
    }

    func testHebrewMonthLabel() {
        XCTAssertEqual(HebrewDate.monthYear("2026-11"), "נובמבר 2026")
        XCTAssertEqual(HebrewDate.monthYear(nil), "")
    }

    func testBadgeAndPointsDecode() throws {
        let home = try API.decoder.decode(StudentHome.self, from: PreviewMode.response(method: "GET", path: "/api/native/student/home"))
        XCTAssertEqual(home.badge?.title?.label, "חוקר מכניקה")
        XCTAssertEqual(home.badge?.frame, "frame_violet")
        XCTAssertEqual(home.points?.level, "להבה")
        XCTAssertEqual(home.points?.nextLevelAt, 500)
    }

    func testRebookOfferDecodes() throws {
        let offer = try XCTUnwrap(PreviewMode.rebook())
        XCTAssertEqual(offer.myResponse, "pending")
        XCTAssertEqual(offer.peers.filter { !$0.isMe && $0.response == "yes" }.count, 1)
    }

    func testBridgeMessages() {
        XCTAssertEqual(BridgeMessage(body: ["type": "lessonLeft", "leftEarly": true, "teacherName": "איתי"]), .lessonLeft(leftEarly: true, teacherName: "איתי"))
        XCTAssertEqual(BridgeMessage(body: ["type": "lessonLeft"]), .lessonLeft(leftEarly: false, teacherName: nil))
        XCTAssertEqual(BridgeMessage(body: ["type": "closeRoom"]), .closeRoom)
        XCTAssertNil(BridgeMessage(body: ["type": "startCall", "kind": "evil", "ref": "x"]))
    }

    func testAvatarAndCelebrations() {
        let center = CelebrationCenter()
        center.fox("כל הכבוד", pose: .cheer)
        XCTAssertNotNil(center.fox)
        center.coins("−2 לוגי")
        XCTAssertEqual(center.coins?.text, "−2 לוגי")
    }
    /// App Store 3.1.3(f): what a parent sees is plain information. It names the website for family accounts and carries no payment wording or link.
    func testParentNoticeHasNoPaymentWordsOrLink() {
        let text = APIError.notAStudentNotice
        XCTAssertTrue(text.contains("lugipod.com"))
        for word in ["תשלום", "לשלם", "מחיר", "מנוי", "₪", "רכיש", "חבילה", "https://", "http://"] {
            XCTAssertFalse(text.contains(word), word)
        }
        XCTAssertEqual(APIError.notAStudent.errorDescription, text)
    }

    func testLinkParentReminderOpensTheParentSheet() {
        XCTAssertEqual(AppRouter.destination(for: "/link-parent"), .linkParent)
        XCTAssertEqual(AppRouter.destination(for: "/alerts"), .alerts)
    }

    func testQuotaCarriesThePackTermsFromTheServer() throws {
        let json = #"{"free_left":0,"free_per_day":20,"pack_left":0,"can_ask":false,"pack_lugis":2,"pack_size":120,"pack_days":14}"#
        let q = try API.decoder.decode(Quota.self, from: Data(json.utf8))
        XCTAssertEqual(q.packLugis, 2)
        XCTAssertEqual(q.packSize, 120)
        XCTAssertEqual(q.packDays, 14)
        XCTAssertEqual(q.remaining, 0)
    }

    func testOnlyDemoAccountsMayUseThePasswordDoor() {
        XCTAssertTrue(AuthStore.emailLoginAllowed("demo.student@lugipod.demo"))
        XCTAssertTrue(AuthStore.emailLoginAllowed("  Demo.Student@Lugipod.Demo "))
        XCTAssertFalse(AuthStore.emailLoginAllowed("student@gmail.com"))
        XCTAssertFalse(AuthStore.emailLoginAllowed("lugipod@gmail.com"))
        XCTAssertFalse(AuthStore.emailLoginAllowed("x@lugipod.demo.evil.com"))
    }

    /// The bug: copying a picture from WhatsApp and pasting it into Lugichat typed text ("blob") instead of attaching the picture.
    func testPastingAPictureAttachesItInsteadOfTypingText() {
        let view = PasteTextView()
        var received: UIImage?
        view.onImage = { received = $0 }
        UIPasteboard.general.image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        XCTAssertTrue(view.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
        view.paste(nil)
        XCTAssertNotNil(received)
        XCTAssertEqual(view.text, "")
    }

    func testShareBridgeOpenRequestIsTakenOnce() throws {
        ShareBridge.setOpenRequest(kind: "lugichat", id: "chat-1")
        guard let first = ShareBridge.takeOpenRequest() else { throw XCTSkip("no keychain access in this build") }
        XCTAssertEqual(first.kind, "lugichat")
        XCTAssertEqual(first.id, "chat-1")
        XCTAssertNil(ShareBridge.takeOpenRequest())
    }

    func testSavedConversationRowDecodes() throws {
        let json = #"{"id":"c1","title":"שיחה עם תמונה","lastAt":"2026-11-09T12:00:00.123Z","snippet":"","hasImage":true}"#
        let chat = try API.decoder.decode(ChatSummary.self, from: Data(json.utf8))
        XCTAssertEqual(chat.id, "c1")
        XCTAssertTrue(chat.hasImage)
    }
}
