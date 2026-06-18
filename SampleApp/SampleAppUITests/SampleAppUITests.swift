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

final class SampleAppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launchEnvironment = ["UITEST_DISABLE_ANIMATIONS": "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testCoverFadeDismissWithSwiftUIDismissCanPresentSameRouteAgain() {
        openLanding()

        tap(A11y.homeShowMessageButton)
        assertExists(A11y.messageText)

        tap(A11y.messageDismissSwiftUIButton)
        assertGone(A11y.messageText)

        tap(A11y.homeShowMessageButton)
        assertExists(A11y.messageText)

        tap(A11y.messageDismissUnwindButton)
        assertGone(A11y.messageText)

        tap(A11y.homeShowMessageButton)
        assertExists(A11y.messageText)
    }

    func testInactiveBranchRouteRequestActivatesBranchAndResumesPresentation() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsPresentHomeMessageButton)

        assertExists(A11y.homeWelcome)
        assertExists(A11y.messageText)
    }

    func testProfileRequestFromSettingsReroutesToLoginThenContinuesToProfile() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsProfileButton)
        assertExists(A11y.loginTitle)
        assertLabel(A11y.loginWindowEnvironmentValue, contains: "forwarded from app window")

        tap(A11y.loginButton)
        assertExists(A11y.profileTitle)
        assertExists(A11y.homeWelcome)
    }

    func testPushReplacementActionHooksAndBranchActions() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsSaveAppearanceButton)
        assertExists(A11y.appearanceTitle)
        assertLabel(A11y.appearanceSavedCount, contains: "Saved 1 time(s)")

        tap(A11y.appearanceSaveButton)
        assertLabel(A11y.appearanceSavedCount, contains: "Saved 2 time(s)")

        tap(A11y.appearanceRePresentButton)
        assertExists(A11y.appearanceTitle)

        tap(A11y.appearancePresentAuthenticationButton)
        assertExists(A11y.authenticationTitle)
    }

    func testUnwindToLandingThenPresentRouteInDifferentBranch() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsAppearanceButton)
        assertExists(A11y.appearanceTitle)

        tap(A11y.appearanceUnwindToLandingPresentMessageButton)
        assertExists(A11y.homeWelcome)
        assertExists(A11y.messageText)
        assertGone(A11y.appearanceTitle)
    }

    func testHighPriorityRerouteReplacementWindowEnvironmentAndLoginContinuation() {
        openLanding()

        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)
        assertLabel(A11y.loginWindowEnvironmentValue, contains: "forwarded from app window")

        tap(A11y.loginReplaceHighPriorityButton)
        assertExists(A11y.replacementTitle)
        assertLabel(A11y.replacementWindowEnvironmentValue, contains: "forwarded from app window")

        tap(A11y.replacementDismissButton)
        assertGone(A11y.replacementTitle)

        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)

        tap(A11y.loginPresentAlertButton)
        assertExists(A11y.alertText)

        tap(A11y.alertDismissSwiftUIButton)
        assertGone(A11y.alertText)

        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)

        tap(A11y.loginPresentAlertButton)
        assertExists(A11y.alertText)

        tap(A11y.alertDismissUnwindButton)
        assertGone(A11y.alertText)

        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)

        tap(A11y.loginButton)
        assertExists(A11y.profileTitle)

        tap(A11y.profileSignOutButton)
        assertExists(A11y.startButton)
    }

    func testDroppedUndeclaredMissingUnwindAndActionDispatchRemainStable() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsPresentDroppedRouteButton)
        assertGone(A11y.droppedRouteText)
        assertExists(A11y.settingsMissingUnwindButton)

        tap(A11y.settingsPresentUndeclaredRouteButton)
        assertGone(A11y.undeclaredRouteText)
        assertExists(A11y.settingsMissingUnwindButton)

        tap(A11y.settingsMissingUnwindButton)
        assertLabel(A11y.settingsMissingUnwindResult, contains: "Missing unwind: false")

        tap(A11y.settingsNewEmojiButton)
        tapHomeTab()
        assertLabel(A11y.homeEmojiValue, contains: "⚡️")
    }
}

private extension SampleAppUITests {
    func openLanding() {
        tap(A11y.startButton)
        assertExists(A11y.homeWelcome)
    }

    func tapHomeTab() {
        tapTab(named: "Home", identifier: A11y.homeTab)
    }

    func tapSettingsTab() {
        tapTab(named: "Settings", identifier: A11y.settingsTab)
    }

    func tapTab(named title: String, identifier: String) {
        let identified = element(identifier)
        if identified.waitForExistence(timeout: 1) {
            identified.tap()
            return
        }

        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "Expected tab \(title) to exist")
        tab.tap()
    }

    func tap(_ identifier: String) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Expected \(identifier) to exist")

        for _ in 0..<4 where target.isHittable == false {
            app.swipeUp()
        }

        XCTAssertTrue(target.isHittable, "Expected \(identifier) to be hittable")
        target.tap()
    }

    func assertExists(_ identifier: String) {
        XCTAssertTrue(element(identifier).waitForExistence(timeout: 5), "Expected \(identifier) to exist")
    }

    func assertGone(_ identifier: String) {
        let target = element(identifier)
        let deadline = Date().addingTimeInterval(5)

        while target.exists && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertFalse(target.exists, "Expected \(identifier) to be gone")
    }

    func assertLabel(_ identifier: String, contains expectedValue: String) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
        XCTAssertTrue(
            target.label.contains(expectedValue) || target.valueDescription.contains(expectedValue),
            "Expected \(identifier) label or value to contain \(expectedValue). label=\(target.label), value=\(target.valueDescription)"
        )
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}

private extension XCUIElement {
    var valueDescription: String {
        if let value = value as? String {
            return value
        }

        return ""
    }
}

private enum A11y {
    static let startButton = "sample.start.button"

    static let homeTab = "sample.tab.home"
    static let settingsTab = "sample.tab.settings"

    static let homeWelcome = "sample.home.welcome"
    static let homeShowMessageButton = "sample.home.show-message"
    static let homeProfileButton = "sample.home.profile"
    static let homeEmojiValue = "sample.home.emoji-value"

    static let settingsAppearanceButton = "sample.settings.appearance"
    static let settingsProfileButton = "sample.settings.profile"
    static let settingsSaveAppearanceButton = "sample.settings.save-appearance"
    static let settingsNewEmojiButton = "sample.settings.new-emoji"
    static let settingsPresentHomeMessageButton = "sample.settings.present-home-message"
    static let settingsPresentDroppedRouteButton = "sample.settings.present-dropped-route"
    static let settingsPresentUndeclaredRouteButton = "sample.settings.present-undeclared-route"
    static let settingsMissingUnwindButton = "sample.settings.missing-unwind"
    static let settingsMissingUnwindResult = "sample.settings.missing-unwind-result"

    static let appearanceTitle = "sample.appearance.title"
    static let appearanceRePresentButton = "sample.appearance.re-present"
    static let appearancePresentAuthenticationButton = "sample.appearance.present-authentication"
    static let appearanceUnwindToLandingPresentMessageButton = "sample.appearance.unwind-landing-present-message"
    static let appearanceSaveButton = "sample.appearance.save"
    static let appearanceSavedCount = "sample.appearance.saved-count"

    static let authenticationTitle = "sample.authentication.title"

    static let messageText = "sample.message.text"
    static let messageDismissUnwindButton = "sample.message.dismiss-unwind"
    static let messageDismissSwiftUIButton = "sample.message.dismiss-swiftui"

    static let alertText = "sample.alert.text"
    static let alertDismissUnwindButton = "sample.alert.dismiss-unwind"
    static let alertDismissSwiftUIButton = "sample.alert.dismiss-swiftui"

    static let loginTitle = "sample.login.title"
    static let loginWindowEnvironmentValue = "sample.login.window-environment"
    static let loginButton = "sample.login.button"
    static let loginReplaceHighPriorityButton = "sample.login.replace-high-priority"
    static let loginPresentAlertButton = "sample.login.present-alert"

    static let replacementTitle = "sample.replacement.title"
    static let replacementWindowEnvironmentValue = "sample.replacement.window-environment"
    static let replacementDismissButton = "sample.replacement.dismiss"

    static let profileTitle = "sample.profile.title"
    static let profileSignOutButton = "sample.profile.sign-out"

    static let droppedRouteText = "sample.dropped-route.text"
    static let undeclaredRouteText = "sample.undeclared-route.text"
}
