import XCTest

/// App Store screenshots from the REAL app against the live server, signed in as the App Review demo student. Runs only in the
/// "Store screenshots" workflow (it needs the demo password in the TEST_RUNNER_STORE_SHOTS_PASSWORD environment variable and a real
/// Secrets.xcconfig); everywhere else it is skipped. Photographs are written to STORE_SHOTS_DIR (default /tmp/lugipod-store).
final class StoreShotsUITests: XCTestCase {
    private var dir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["STORE_SHOTS_DIR"] ?? "/tmp/lugipod-store")
    }

    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        if b.waitForExistence(timeout: 10) { b.tap() }
    }

    func testStoreScreens() throws {
        guard let password = ProcessInfo.processInfo.environment["STORE_SHOTS_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("store screenshots run only in the Store screenshots workflow")
        }
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()

        // Sign in with the review account's email and password (the quiet fallback on the first screen).
        let emailLink = app.buttons["כניסה עם אימייל במקום"]
        XCTAssertTrue(emailLink.waitForExistence(timeout: 30), "first screen")
        emailLink.tap()
        let email = app.textFields["email-input"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("demo.student@lugipod.demo")
        let pass = app.secureTextFields["password-input"]
        pass.tap()
        pass.typeText(password)
        app.buttons["כניסה"].firstMatch.tap()

        // Home: the bottom bar appears, then the data.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "לוגיצ׳אט")).firstMatch.waitForExistence(timeout: 60), "signed in")
        sleep(8)
        shoot("01-home")

        // The group and its lessons.
        let group = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "מתמטיקה")).firstMatch
        if group.waitForExistence(timeout: 10) {
            group.tap()
            sleep(5)
            shoot("02-group")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() } else { app.swipeRight() }
            sleep(2)
        }

        tab(app, "תרגול"); sleep(6); shoot("03-practice")
        tab(app, "לוגיצ׳אט"); sleep(4); shoot("04-lugichat")
        tab(app, "חברים"); sleep(6); shoot("05-friends")
        tab(app, "עוד"); sleep(4); shoot("06-more")
    }
}
