import XCTest

final class GlobalRoutesTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testGlobal2FAFromRootAndDetailRetainsTheInvokingFlow() {
        let app = launch()
        tap("2fa", app)
        assertEnvironment(app)
        tap("done", app)
        tap("detail", app)
        tap("2fa", app)
        assertEnvironment(app)
        tap("done", app)
        XCTAssertEqual(app.staticTexts["sample.globals.location"].label, "App detail")
    }

    func testFadeLockBlocksCoveredNavigationAndUnlocksExplicitly() {
        let app = launch()
        tap("lock", app)
        assertProtection(app)
        assertEnvironment(app)
        tap("covered-request", app)
        XCTAssertTrue(app.staticTexts["sample.globals.attempted"].waitForExistence(timeout: 5))
        assertProtection(app)
        tap("unlock", app)
        XCTAssertTrue(app.buttons["sample.globals.lock"].waitForExistence(timeout: 5))
        tap("2fa", app)
        assertEnvironment(app)
    }

    func testUnprotectedGlobalSuspendsProtectionAndAllowsCrawlback() {
        let app = launch()
        tap("lock", app)
        tap("over-lock", app)
        assertEnvironment(app)
        tap("crawlback", app)
        XCTAssertTrue(app.buttons["sample.globals.back"].waitForExistence(timeout: 5))
        tap("back", app)
        XCTAssertTrue(app.buttons["sample.globals.lock"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["sample.globals.passcode"].exists)
    }

    func testDeclaredChildSuspendsProtectionAndRestoresItOnReturn() {
        let app = launch()
        tap("lock", app)
        tap("help", app)
        XCTAssertTrue(app.staticTexts["sample.globals.overlay-title"].waitForExistence(timeout: 5))
        assertEnvironment(app)
        tap("done", app)
        assertProtection(app)
        tap("covered-request", app)
        assertProtection(app)
        tap("child", app)
        XCTAssertTrue(app.staticTexts["sample.globals.overlay-title"].waitForExistence(timeout: 5))
        tap("crawlback", app)
        XCTAssertTrue(app.buttons["sample.globals.back"].waitForExistence(timeout: 5))
    }

    func testProtectedGlobalCanCoverAnotherProtectedGlobal() {
        let app = launch()
        tap("lock", app)
        tap("protected-overlay", app)
        assertEnvironment(app)
        tap("crawlback", app)
        XCTAssertTrue(app.staticTexts["sample.globals.overlay-title"].exists)
        tap("done", app)
        assertProtection(app)
        tap("unlock", app)
        XCTAssertTrue(app.buttons["sample.globals.lock"].waitForExistence(timeout: 5))
    }

    func testLockPreservesAppTextAndGlobalAuthenticationInput() {
        let app = launch()
        let note = app.textFields["sample.globals.note"]
        note.tap()
        note.typeText("Retained app state\n")
        tap("lock", app)
        tap("over-lock", app)
        let code = app.textFields["sample.globals.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap()
        code.typeText("123456\n")
        XCTAssertEqual(code.value as? String, "123456")
        tap("done", app)
        tap("unlock", app)
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, "Retained app state")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--scenario=global-routes"]
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    private func assertProtection(_ app: XCUIApplication) {
        let status = app.staticTexts["sample.globals.protection"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Protection active")
    }

    private func assertEnvironment(_ app: XCUIApplication) {
        let status = app.staticTexts.matching(identifier: "sample.globals.environment").allElementsBoundByIndex.last
        XCTAssertNotNil(status)
        guard let status else { return }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Same window: true", "inherited configuration"),
            object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, status.label)
    }

    private func tap(_ suffix: String, _ app: XCUIApplication) {
        let candidates = app.buttons.matching(identifier: "sample.globals.\(suffix)")
        _ = candidates.firstMatch.waitForExistence(timeout: 2)
        for _ in 0..<4 where !candidates.allElementsBoundByIndex.contains(where: \.isHittable) {
            app.swipeUp()
        }
        let target = candidates.allElementsBoundByIndex.reversed().first(where: \.isHittable) ?? candidates.firstMatch
        XCTAssertTrue(target.exists)
        XCTAssertTrue(target.isHittable)
        target.tap()
    }
}
