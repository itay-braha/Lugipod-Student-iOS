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

    func testHomeDecodes() throws {
        let data = PreviewMode.response(method: "GET", path: "/api/native/student/home")
        let home = try API.decoder.decode(StudentHome.self, from: data)
        XCTAssertEqual(home.lessons.count, 3)
        XCTAssertEqual(home.lessons.first?.phase, .live)
        XCTAssertEqual(home.lugichat?.freeLeft, 14)
        XCTAssertEqual(home.subjects.filter(\.mine).count, 2)
        XCTAssertEqual(home.dailyChallenge.streak, 6)
    }

    func testQuotaDecodesWithMissingFields() throws {
        let q = try API.decoder.decode(Quota.self, from: Data("{\"free_left\":3}".utf8))
        XCTAssertEqual(q.freeLeft, 3)
        XCTAssertNil(q.packLeft)
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
}
