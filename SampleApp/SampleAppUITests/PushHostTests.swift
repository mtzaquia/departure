//
//  Copyright (c) 2026 @mtzaquia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import XCTest

final class PushHostTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testSheetWithItsOwnStack() { launch("explicit"); tap("sheet"); pushTwice() }
    func testCoverWithItsOwnStack() { launch("explicit"); tap("cover"); pushTwice() }
    func testFadeCoverWithItsOwnStack() { launch("explicit"); tap("fade"); pushTwice() }
    func testPushedChildUsesAutomaticHost() { launch("explicit"); pushTwice() }
    func testRootStackWithExplicitHost() { launch("explicit"); pushTwice() }
    func testRouterInsideOuterStack() { launch("outer"); pushTwice() }
    func testRootStackWithoutExplicitHostExplainsRequiredPlacement() {
        launch("missing")
        tap("push-first")
        assertConsole(expectsPlacementDiagnostic: true)
    }
    func testBranchStacks() {
        launch("branch")
        pushTwice()
        app.tabBars.buttons["Second"].tap()
        pushTwice()
        app.tabBars.buttons["First"].tap()
        XCTAssertTrue(app.staticTexts["sample.push-host.second"].waitForExistence(timeout: 5))
        assertConsole()
    }
    func testPushPendingBeforeAutomaticSlotIsReady() {
        launch("explicit")
        pushImmediateChild()
    }
    func testCoverChildCanPushFromTask() {
        launch("explicit")
        tap("cover")
        pushImmediateChild()
    }
    func testSheetChildCanPushFromTask() {
        launch("explicit")
        tap("sheet")
        pushImmediateChild()
    }
    func testFadeCoverChildCanPushFromTask() {
        launch("explicit")
        tap("fade")
        pushImmediateChild()
    }

    private func pushImmediateChild() {
        tap("push-immediate")
        let appeared = app.staticTexts["sample.push-host.second"].waitForExistence(timeout: 5)
        assertConsole()
        XCTAssertTrue(appeared)
    }
    func testPendingPushIsPresentedWhenStackSideHostIsInstalled() {
        launch("late")
        tap("push-first")
        setExplicitHost(true)
        XCTAssertTrue(app.staticTexts["sample.push-host.first"].waitForExistence(timeout: 5))
        tap("push-second")
        XCTAssertTrue(app.staticTexts["sample.push-host.second"].waitForExistence(timeout: 5))
        assertConsole()
    }
    func testAutomaticHostTakesOverWhenExplicitHostLeaves() {
        launch("handover")
        setExplicitHost(false)
        pushTwice()
    }
    func testPlainSheetNeedsNoStack() { launch("explicit"); tap("plain-sheet"); closePlain() }
    func testPlainCoverNeedsNoStack() { launch("explicit"); tap("plain-cover"); closePlain() }

    private func launch(_ scenario: String) {
        app = XCUIApplication()
        app.launchArguments = ["--push-host-probe=\(scenario)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sample.push-host.root"].waitForExistence(timeout: 8))
    }
    private func pushTwice() {
        tap("push-first")
        XCTAssertTrue(app.staticTexts["sample.push-host.first"].waitForExistence(timeout: 5))
        tap("push-second")
        XCTAssertTrue(app.staticTexts["sample.push-host.second"].waitForExistence(timeout: 5))
        tap("unwind")
        XCTAssertTrue(app.buttons["sample.push-host.push-second"].waitForExistence(timeout: 5))
        // Re-push exercises iOS 17 nil write-back and host identity handling.
        tap("push-second")
        XCTAssertTrue(app.staticTexts["sample.push-host.second"].waitForExistence(timeout: 5))
        assertConsole()
    }
    private func closePlain() {
        XCTAssertTrue(app.staticTexts["sample.push-host.plain"].waitForExistence(timeout: 5))
        tap("close")
        XCTAssertTrue(app.buttons["sample.push-host.push-first"].waitForExistence(timeout: 5))
        assertConsole()
    }
    private func assertConsole(expectsPlacementDiagnostic: Bool = false) {
        tap("read-console")
        let outputs = app.staticTexts.matching(identifier: "sample.push-host.console")
        let output = outputs.allElementsBoundByIndex.reversed().first(where: \.isHittable) ?? outputs.firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        let captured = XCTNSPredicateExpectation(predicate:
            NSPredicate(format: "label BEGINSWITH %@", "SwiftUI navigation warnings:"), object: output)
        XCTAssertEqual(XCTWaiter.wait(for: [captured], timeout: 5), .completed, output.label)
        XCTAssertTrue(output.label.contains("SwiftUI navigation warnings: 0"), output.label)
        XCTAssertFalse(output.label.contains("Entries inspected: 0"), output.label)
        if expectsPlacementDiagnostic {
            XCTAssertTrue(output.label.contains("Departure placement diagnostics: 1"), output.label)
            XCTAssertTrue(output.label.contains("Root().routing()"), output.label)
        }
        let attachment = XCTAttachment(string: output.label + "\n\n" + (output.value as? String ?? ""))
        attachment.name = name + " console"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func tap(_ suffix: String) {
        let matches = app.buttons.matching(identifier: "sample.push-host.\(suffix)")
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5))
        let button = matches.allElementsBoundByIndex.reversed().first(where: \.isHittable) ?? matches.firstMatch
        button.tap()
    }

    private func setExplicitHost(_ enabled: Bool) {
        tap("explicit")
        // Installing the host immediately reveals the pending destination and
        // removes this root's status from accessibility. The caller asserts that
        // destination; removal keeps this status visible for a direct assertion.
        guard !enabled else { return }
        let status = app.staticTexts["sample.push-host.explicit-state"]
        let changed = XCTNSPredicateExpectation(predicate:
            NSPredicate(format: "label == %@", enabled ? "Enabled" : "Disabled"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }
}
