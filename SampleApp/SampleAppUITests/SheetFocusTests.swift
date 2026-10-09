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

final class SheetFocusTests: XCTestCase {
    func testBranchSheetRetainsFocusAndReopensAfterNativeDismissal() {
        verifyFocusAndReopening(root: false)
    }

    func testRootSheetRetainsFocusAndReopensAfterNativeDismissal() {
        verifyFocusAndReopening(root: true)
    }

    func testReplacementShowsFreshDestinationAndSurvivesOldDismissal() {
        // A root declaration owns one modal slot; inherited branch lookup may append deeper.
        let app = launch(root: true)
        defer { app.terminate() }
        tap("sample.sheet-focus.present", in: app)
        let number = app.staticTexts["sample.sheet-focus.number"]
        XCTAssertTrue(number.waitForExistence(timeout: 5))
        let identity = app.staticTexts["sample.sheet-focus.identity"].label
        tap("sample.sheet-focus.replace", in: app)
        let successor = NSPredicate(format: "label == %@", "Sheet 2")
        expectation(for: successor, evaluatedWith: number)
        waitForExpectations(timeout: 8)
        XCTAssertNotEqual(app.staticTexts["sample.sheet-focus.identity"].label, identity)
        let field = app.textFields["sample.sheet-focus.field"]
        field.tap()
        field.typeText("Successor")
        XCTAssertEqual(field.value as? String, "Successor")
        tap("sample.sheet-focus.unwind", in: app)
        XCTAssertTrue(app.buttons["sample.sheet-focus.present"].waitForExistence(timeout: 5))
        XCTAssertFalse(number.exists)
    }

    func testBranchSheetSwipeDismissalAllowsReopening() {
        let app = launch()
        defer { app.terminate() }
        tap("sample.sheet-focus.present", in: app)
        let number = app.staticTexts["sample.sheet-focus.number"]
        XCTAssertTrue(number.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["sample.sheet-focus.present"].waitForExistence(timeout: 5))
        XCTAssertFalse(number.exists)
        tap("sample.sheet-focus.present", in: app)
        XCTAssertTrue(number.waitForExistence(timeout: 5))
    }

    private func verifyFocusAndReopening(root: Bool) {
        let app = launch(root: root)
        defer { app.terminate() }
        tap("sample.sheet-focus.present", in: app)
        let field = app.textFields["sample.sheet-focus.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "First presentation must contain the destination")
        let identity = app.staticTexts["sample.sheet-focus.identity"].label
        field.tap()
        let responder = app.staticTexts["sample.sheet-focus.responder"]
        let enoughSamples = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            let parts = element.label.components(separatedBy: ",")
            return parts.count == 6 && (Int(parts[5]) ?? 0) >= 12
        }
        let sampled = XCTNSPredicateExpectation(predicate: enoughSamples, object: responder)
        XCTAssertEqual(XCTWaiter.wait(for: [sampled], timeout: 5), .completed, responder.label)
        let initialNative = responder.label.components(separatedBy: ",")
        XCTAssertEqual(Array(initialNative.prefix(4)), ["1", "0", "0", "true"], responder.label)
        let nativeIdentity = initialNative[4]
        field.typeText("Coffee")
        XCTAssertEqual(field.value as? String, "Coffee")
        XCTAssertEqual(app.staticTexts["sample.sheet-focus.focus"].label, "focused")
        XCTAssertEqual(app.staticTexts["sample.sheet-focus.identity"].label, identity)
        let retainedNative = responder.label.components(separatedBy: ",")
        XCTAssertEqual(Array(retainedNative.prefix(4)), ["1", "0", "0", "true"], responder.label)
        XCTAssertEqual(retainedNative[4], nativeIdentity)
        tap("sample.sheet-focus.done", in: app)
        tap("sample.sheet-focus.save", in: app)
        XCTAssertTrue(app.staticTexts["sample.sheet-focus.error"].waitForExistence(timeout: 3))
        field.typeText(" beans")
        XCTAssertEqual(field.value as? String, "Coffee beans")
        XCTAssertEqual(app.staticTexts["sample.sheet-focus.focus"].label, "focused")
        XCTAssertEqual(app.staticTexts["sample.sheet-focus.identity"].label, identity)
        let refocusedNative = responder.label.components(separatedBy: ",")
        XCTAssertEqual(Array(refocusedNative.prefix(4)), ["2", "1", "0", "true"], responder.label)
        XCTAssertEqual(refocusedNative[4], nativeIdentity)
        tap("sample.sheet-focus.dismiss", in: app)
        XCTAssertTrue(app.buttons["sample.sheet-focus.present"].waitForExistence(timeout: 5))
        tap("sample.sheet-focus.present", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["sample.sheet-focus.identity"].label, identity)
    }

    func testImmediatePresentationAndUnwindCanBeRepeated() {
        let app = launch(root: true)
        defer { app.terminate() }
        tap("sample.sheet-focus.cycle", in: app)
        let cycles = app.staticTexts["sample.sheet-focus.cycles"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Cycles: 10"), object: cycles)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 20), .completed, cycles.label)
        tap("sample.sheet-focus.present", in: app)
        XCTAssertTrue(app.textFields["sample.sheet-focus.field"].waitForExistence(timeout: 5))
    }

    private func launch(root: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--sheet-focus-probe"] + (root ? ["--sheet-focus-root"] : [])
        app.launch()
        return app
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }
}
