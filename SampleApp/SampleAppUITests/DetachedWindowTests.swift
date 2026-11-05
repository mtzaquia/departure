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

final class DetachedWindowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHighAndCriticalSheetsKeepWindowAndToolbarPreferences() {
        let app = launch()
        defer { app.terminate() }
        tap("present", in: app)
        assertPreferences(in: app)
        tap("critical", in: app)
        assertPreferences(in: app, priority: "critical")
        tap("dismiss", in: app)
        assertPreferences(in: app)
        tap("dismiss", in: app)
        XCTAssertTrue(app.buttons["sample.detached-window.present"].waitForExistence(timeout: 5))
        tap("present", in: app)
        assertPreferences(in: app)
    }

    func testSheetSurvivesRotationAndAppSwitcherSnapshot() {
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        tap("present", in: app)
        assertPreferences(in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        tap("inspect", in: app)
        assertPreferences(in: app, inspection: 1)
        XCUIDevice.shared.press(.home)
        app.activate()
        tap("inspect", in: app)
        assertPreferences(in: app, inspection: 2)
        XCUIDevice.shared.orientation = .portrait
        tap("dismiss", in: app)
        XCTAssertTrue(app.buttons["sample.detached-window.present"].waitForExistence(timeout: 5))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--detached-window-probe"]
        app.launch()
        return app
    }

    private func assertPreferences(in app: XCUIApplication, priority: String = "high", inspection: Int = 0) {
        let reports = app.staticTexts.matching(identifier: "sample.detached-window.report")
        let report = reports.allElementsBoundByIndex.last ?? reports.firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        let expected = ["Priority: \(priority)", "Orientation matches: true", "Status bar matches: true",
                        "Detached window: true", "Inspection: \(inspection)"]
        var checks = expected
        if #available(iOS 27.1, *) {
            checks += ["Toolbars match: true"]
            // SwiftUI resolves this policy only on devices with vertical-bar support.
            // Keep a strict assertion for the Duo simulator regression fixture.
            if ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4" {
                checks += ["Source toolbar: disabled", "Elevated toolbar: disabled", "Presentation toolbar: disabled"]
            }
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates:
            checks.map { NSPredicate(format: "label CONTAINS %@", $0) })
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: report)], timeout: 8),
                       .completed, report.label)
    }

    private func tap(_ suffix: String, in app: XCUIApplication) {
        let matches = app.buttons.matching(identifier: "sample.detached-window.\(suffix)")
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5))
        let button = matches.allElementsBoundByIndex.reversed().first(where: \.isHittable) ?? matches.firstMatch
        button.tap()
    }
}
