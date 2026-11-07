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
}
