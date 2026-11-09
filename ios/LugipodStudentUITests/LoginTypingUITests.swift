import XCTest

/// Drives the real app on a simulator the way a first-time user does: opens it, taps the phone box, types with the keyboard, and checks (and
/// photographs) what is on screen. Added after testers reported that the digits they typed in the sign-up phone box could not be seen.
final class LoginTypingUITests: XCTestCase {
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let dir = URL(fileURLWithPath: "/tmp/lugipod-ui")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LUGIPOD_SHOW_EMAIL"] = "1"   // the email link is hidden in the real app (five taps on the fox)
        app.launch()
        return app
    }

    func testTypedPhoneNumberIsVisibleAndFormatted() throws {
        let app = launch()
        let input = app.textFields["phone-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30), "the phone box is on the first screen")
        shoot(app, "ui-1-empty")

        input.tap()
        input.typeText("501")
        let shown = app.staticTexts["phone-display"]
        XCTAssertTrue(shown.waitForExistence(timeout: 5), "typed digits are drawn on screen")
        XCTAssertEqual(shown.label, "50-1")                  // the dash appears by itself
        shoot(app, "ui-2a-typing")
        input.typeText("234567")
        XCTAssertEqual(shown.label, "50-123-4567")
        shoot(app, "ui-2-typed")
    }

    func testLeadingZeroAndExtraDigitsAreIgnored() throws {
        let app = launch()
        let input = app.textFields["phone-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("0501234567")                          // someone who types the 0 anyway
        let shown = app.staticTexts["phone-display"]
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        XCTAssertEqual(shown.label, "50-123-4567")
        shoot(app, "ui-3-typed-with-zero-ignored")
        input.typeText("99")                                  // more digits than a number has change nothing
        XCTAssertEqual(shown.label, "50-123-4567")
        input.typeText(XCUIKeyboardKey.delete.rawValue)       // and backspace takes the last digit off
        XCTAssertEqual(shown.label, "50-123-456")
    }

    func testAnotherFirstDigitIsRefused() throws {
        let app = launch()
        let input = app.textFields["phone-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 30))
        input.tap()
        input.typeText("3")                                   // not a mobile number: nothing appears
        XCTAssertFalse(app.staticTexts["phone-display"].waitForExistence(timeout: 2))
        input.typeText("52")
        XCTAssertEqual(app.staticTexts["phone-display"].label, "52")
    }

    func testEmailFallbackFieldsShowWhatIsTyped() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["כניסה עם אימייל במקום"].waitForExistence(timeout: 30))
        app.buttons["כניסה עם אימייל במקום"].tap()
        let email = app.textFields["email-input"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("tester@example.com")
        XCTAssertEqual(email.value as? String, "tester@example.com")
        shoot(app, "ui-4-email")
        let secret = app.secureTextFields["password-input"]
        secret.tap()
        secret.typeText("hunter2hunter2")
        shoot(app, "ui-4b-password")      // the dots must be visible
    }
}
