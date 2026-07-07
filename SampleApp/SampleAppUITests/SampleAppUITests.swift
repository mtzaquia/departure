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

    func testBranchCrawlActivationAndStackPersistence() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tapHomeTab()
        assertExists(A11y.homeWelcome)

        tapSettingsTab()
        assertExists(A11y.authenticationTitle)
        assertGone(A11y.settingsAuthenticationButton)

        tap(A11y.authenticationUnwindToNearestBranchButton)
        assertGone(A11y.authenticationTitle)
        assertExists(A11y.settingsAuthenticationButton)

        tap(A11y.settingsAppearanceButton)
        assertExists(A11y.appearanceTitle)

        tap(A11y.appearancePresentAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tap(A11y.authenticationUnwindToNearestBranchButton)
        assertGone(A11y.authenticationTitle)
        assertGone(A11y.appearanceTitle)
        assertExists(A11y.settingsAuthenticationButton)
        assertExists(A11y.settingsAppearanceButton)

        tap(A11y.settingsPresentHomeMessageButton)
        assertExists(A11y.homeWelcome)
        assertExists(A11y.messageText)
        assertLabel(A11y.messagePresentationSource, contains: "top-level branched scope")
    }

    func testModalArbitrationAndChainingFromPushedBranch() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tap(A11y.authenticationPresentTopLevelSheetButton)
        assertExists(A11y.topLevelSheetText)
        assertLabel(A11y.topLevelSheetPresentationSource, contains: "top-level branched scope")

        tap(A11y.topLevelSheetDismissButton)
        assertGone(A11y.topLevelSheetText)
        assertExists(A11y.authenticationTitle)

        setSwitch(A11y.authenticationAttachLocalRouteToggle, on: true)

        tap(A11y.authenticationPresentTopLevelSheetButton)
        assertExists(A11y.topLevelSheetText)
        assertLabel(A11y.topLevelSheetPresentationSource, contains: "authentication settings scope")

        tap(A11y.topLevelSheetPresentCoverButton)
        assertExists(A11y.topLevelCoverText)
        assertGone(A11y.topLevelSheetText)

        tap(A11y.topLevelCoverPresentReplacementButton)
        assertExists(A11y.topLevelReplacementCoverText)
        assertGone(A11y.topLevelCoverText)

        tap(A11y.topLevelReplacementCoverDismissButton)
        assertGone(A11y.topLevelReplacementCoverText)
        assertGone(A11y.topLevelSheetText)
        assertExists(A11y.authenticationTitle)
        assertGone(A11y.settingsAuthenticationButton)
    }

    func testModalFromModalReplacesLocalBranchModal() {
        openLanding()

        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)

        tap(A11y.loginButton)
        assertExists(A11y.profileTitle)

        tap(A11y.profilePresentTopLevelSheetButton)
        assertExists(A11y.topLevelSheetText)
        assertLabel(A11y.topLevelSheetPresentationSource, contains: "top-level branched scope")
        assertGone(A11y.profileTitle)

        tap(A11y.topLevelSheetDismissButton)
        assertGone(A11y.topLevelSheetText)
        assertGone(A11y.profileTitle)
        assertExists(A11y.homeWelcome)
    }

    func testHighPriorityWindowReplacementAndContinuation() {
        openLanding()

        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)
        assertLabel(A11y.loginIsPresented, contains: "true")
        assertLabel(A11y.loginWindowEnvironmentValue, contains: "forwarded from app window")
        assertLabel(A11y.loginWindowEnvironmentValue, contains: "active")

        tap(A11y.loginReplaceHighPriorityButton)
        assertExists(A11y.replacementTitle)
        assertLabel(A11y.replacementIsPresented, contains: "true")
        assertLabel(A11y.replacementWindowEnvironmentValue, contains: "forwarded from app window")
        assertLabel(A11y.replacementWindowEnvironmentValue, contains: "active")

        tap(A11y.replacementDismissButton)
        assertGone(A11y.replacementTitle)

        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)

        tap(A11y.loginButton)
        assertExists(A11y.profileTitle)

        tap(A11y.profileSignOutButton)
        assertExists(A11y.startButton)
    }

    func testRoutesFromHighPriorityTreeBehaveAsNormalNavigationAndModal() {
        openLanding()

        // Reaching profile while logged out reroutes to the login high-priority cover, starting a
        // high-priority tree.
        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)
        assertLabel(A11y.loginIsPresented, contains: "true")

        // A normal push declared inside the tree navigates within the login stack (it is not
        // blocked the way a normal route before the tree would be).
        tap(A11y.loginIncrementPresentationProbeButton)
        assertLabel(A11y.loginPresentationProbeCount, contains: "Login presentation probe: 1")

        tap(A11y.loginPushDetailButton)
        assertExists(A11y.loginDetailText)

        tap(A11y.loginDetailPresentLoginButton)
        assertGone(A11y.loginDetailText)
        assertExists(A11y.loginTitle)
        assertLabel(A11y.loginPresentationProbeCount, contains: "Login presentation probe: 1")

        // A high-priority sheet declared inside the tree presents as a normal sheet over login
        // — it must not escalate/replace the login cover, so login stays in the hierarchy behind it.
        tap(A11y.loginPresentHighPrioritySheetButton)
        assertExists(A11y.loginNoticeText)
        assertLabel(A11y.loginNoticeText, contains: "true")
        assertExists(A11y.loginTitle)

        tap(A11y.loginNoticeDismissButton)
        assertGone(A11y.loginNoticeText)
        assertExists(A11y.loginTitle)
    }

    func testCriticalPriorityPresentationOverlaysAndReplacesAboveHighPriorityTree() {
        openLanding()

        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)
        assertLabel(A11y.loginIsPresented, contains: "true")
        assertLabel(A11y.loginPresentationProbeCount, contains: "Login presentation probe: 0")
        let loginProbeCoordinate = app.buttons[A11y.loginToolbarIncrementPresentationProbeButton]
            .firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        app.swipeUp()
        let loginCancelCoordinate = app.buttons[A11y.loginCancelButton]
            .firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        tap(A11y.loginPresentCriticalButton)
        assertExists(A11y.criticalText)
        assertLabel(A11y.criticalText, contains: "true")
        assertLabel(A11y.criticalWindowEnvironmentValue, contains: "forwarded from app window")
        assertLabel(A11y.criticalScenePhaseValue, contains: "active")
        assertExists(A11y.loginTitle)

        loginProbeCoordinate.tap()
        assertLabel(A11y.loginPresentationProbeCount, contains: "Login presentation probe: 1")
        assertExists(A11y.criticalText)

        loginCancelCoordinate.tap()
        assertGone(A11y.criticalText)
        assertExists(A11y.loginTitle)

        app.swipeUp()
        tap(A11y.loginPresentCriticalButton)
        assertExists(A11y.criticalText)
        assertLabel(A11y.criticalText, contains: "true")

        tap(A11y.criticalReplaceButton)
        assertExists(A11y.criticalReplacementText)
        assertLabel(A11y.criticalReplacementText, contains: "true")
        assertGone(A11y.criticalText)
        assertExists(A11y.loginTitle)

        tap(A11y.criticalReplacementDismissButton)
        assertGone(A11y.criticalReplacementText)
        assertExists(A11y.loginTitle)
    }

    func testHighPrioritySheetHonorsSwiftUIPresentationPassthrough() {
        openLanding()

        assertLabel(A11y.homePassthroughTapCount, contains: "Behind sheet taps: 0")
        assertLabel(A11y.homeRoutePhase, contains: "Home route phase: active")

        tapSettingsTab()
        tapHomeTab()
        assertLabel(A11y.homeRoutePhase, contains: "Home route phase: active")

        let behindCoordinate = app.buttons[A11y.homePassthroughBehindButton]
            .firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        tap(A11y.homePresentHighPriorityPassthroughSheetButton)
        assertExists(A11y.highPriorityPassthroughSheetText)
        assertLabel(A11y.highPriorityPassthroughSheetText, contains: "true")
        assertLabel(A11y.highPriorityPassthroughSheetRoutePhase, contains: "Route phase: active")
        assertLabel(A11y.homeRoutePhase, contains: "Home route phase: inactive")

        behindCoordinate.tap()
        assertExists(A11y.highPriorityPassthroughSheetText)
        assertLabel(A11y.homePassthroughTapCount, contains: "Behind sheet taps: 1")

        tap(A11y.highPriorityPassthroughSheetDismissButton)
        assertGone(A11y.highPriorityPassthroughSheetText)
    }

    func testHighPrioritySheetScrimBlocksPresentationPassthrough() {
        openLanding()

        assertLabel(A11y.homePassthroughTapCount, contains: "Behind sheet taps: 0")

        let behindCoordinate = app.buttons[A11y.homePassthroughBehindButton]
            .firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        tap(A11y.homePresentHighPriorityBlockingSheetButton)
        assertExists(A11y.highPriorityBlockingSheetText)
        assertLabel(A11y.highPriorityBlockingSheetText, contains: "true")

        behindCoordinate.tap()
        assertLabel(A11y.homePassthroughTapCount, contains: "Behind sheet taps: 0")

        guard element(A11y.highPriorityBlockingSheetDismissButton).exists else {
            return
        }

        tap(A11y.highPriorityBlockingSheetDismissButton)
        assertGone(A11y.highPriorityBlockingSheetText)
    }

    func testSwiftUIDismissSynchronizationAndHandlerTiming() {
        openLanding()

        tap(A11y.homeShowMessageButton)
        assertExists(A11y.messageText)

        tap(A11y.messageDismissSwiftUIButton)
        assertGone(A11y.messageText)

        tap(A11y.homeShowMessageButton)
        assertExists(A11y.messageText)

        tap(A11y.messageDismissUnwindButton)
        assertGone(A11y.messageText)

        tap(A11y.homeShowDismissProbeButton)
        assertExists(A11y.dismissProbeText)

        tap(A11y.dismissProbeDismissButton)
        assertGone(A11y.dismissProbeText)
        assertExists(A11y.messageText)

        tap(A11y.messageDismissUnwindButton)
        assertGone(A11y.messageText)
        assertLabel(A11y.homeDismissProbeHookStatus, contains: "Dismiss probe hooks: 1")
    }

    func testFadeCoverContentStaysInsideItsNavigationStack() {
        openLanding()

        tap(A11y.homeShowNavigationBarFadeButton)
        assertExists(A11y.navigationBarFadeText)
        assertLabel(A11y.navigationBarFadeToolbarTapCount, contains: "Toolbar taps: 0")

        let toolbarButton = app.buttons[A11y.navigationBarFadeToolbarButton]
        XCTAssertTrue(toolbarButton.waitForExistence(timeout: 5), "Expected toolbar button to exist")
        toolbarButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        assertLabel(A11y.navigationBarFadeToolbarTapCount, contains: "Toolbar taps: 1")
    }

    func testUnwindTargetsAcrossBranchContainer() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tap(A11y.authenticationUnwindToNearestBranchButton)
        assertGone(A11y.authenticationTitle)
        assertExists(A11y.settingsAuthenticationButton)
        assertExists(A11y.landing)
        assertLabel(A11y.landingContainerHookStatus, contains: "Container unwind hooks: 1")
        assertLabel(A11y.settingsBranchHookStatus, contains: "Branch unwind hooks: 0")

        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tap(A11y.authenticationUnwindToBranchIDButton)
        assertGone(A11y.authenticationTitle)
        assertExists(A11y.settingsAuthenticationButton)
        assertLabel(A11y.landingContainerHookStatus, contains: "Container unwind hooks: 1")
        assertLabel(A11y.settingsBranchHookStatus, contains: "Branch unwind hooks: 1")

        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tap(A11y.authenticationUnwindToRootButton)
        assertExists(A11y.startButton)
        assertGone(A11y.landing)
        assertLabel(A11y.rootHookStatus, contains: "Root unwind hooks: 1")

        tap(A11y.startShowInfoButton)
        assertExists(A11y.startInfoText)

        tap(A11y.startInfoDismissButton)
        assertGone(A11y.startInfoText)
        assertExists(A11y.startButton)
    }

    func testCapturedLandingUnwindRouteActionFromDeepNavigationPath() {
        openLanding()
        tapSettingsTab()

        assertLabel(A11y.landingContainerHookStatus, contains: "Container unwind hooks: 0")
        assertLabel(A11y.settingsBranchHookStatus, contains: "Branch unwind hooks: 0")

        tap(A11y.settingsAppearanceButton)
        assertExists(A11y.appearanceTitle)

        tap(A11y.appearancePresentAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tap(A11y.authenticationUnwindCapturedLandingButton)
        assertExists(A11y.startButton)
        assertGone(A11y.landing)
        assertGone(A11y.authenticationTitle)
        assertGone(A11y.appearanceTitle)
        assertLabel(A11y.rootHookStatus, contains: "Root unwind hooks: 0")

        openLanding()
        tapSettingsTab()
        assertExists(A11y.settingsAuthenticationButton)
        assertGone(A11y.authenticationTitle)
        assertGone(A11y.appearanceTitle)
        assertLabel(A11y.landingContainerHookStatus, contains: "Container unwind hooks: 0")
        assertLabel(A11y.settingsBranchHookStatus, contains: "Branch unwind hooks: 0")

        tap(A11y.settingsPresentHomeMessageButton)
        assertExists(A11y.homeWelcome)
        assertExists(A11y.messageText)
        assertLabel(A11y.messagePresentationSource, contains: "top-level branched scope")
    }

    func testAppSmokeForActionsResolutionAndDroppedRoutes() {
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

        tapSettingsTab()
        tap(A11y.settingsSaveAppearanceButton)
        assertExists(A11y.appearanceTitle)
        assertLabel(A11y.appearanceSavedCount, contains: "Saved 1 time(s)")

        tap(A11y.appearanceSaveButton)
        assertLabel(A11y.appearanceSavedCount, contains: "Saved 2 time(s)")

        assertLabel(A11y.appearanceValue, contains: "Route value: nil")
        tap(A11y.appearanceRePresentButton)
        assertExists(A11y.appearanceTitle)
        assertLabel(A11y.appearanceValue, contains: "Route value: nil")

        tap(A11y.appearanceRePresentDifferentButton)
        assertExists(A11y.appearanceTitle)
        let changedRouteValue = label(A11y.appearanceValue)
        XCTAssertNotEqual(changedRouteValue, "Route value: nil")

        tap(A11y.appearanceRePresentButton)
        assertExists(A11y.appearanceTitle)
        XCTAssertEqual(label(A11y.appearanceValue), changedRouteValue)

        tap(A11y.appearancePresentAuthenticationButton)
        assertExists(A11y.authenticationTitle)
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

    func setSwitch(_ identifier: String, on: Bool) {
        let target = app.switches[identifier]
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Expected switch \(identifier) to exist")

        let expectedValue = on ? "1" : "0"
        if target.valueDescription != expectedValue {
            XCTAssertTrue(target.isHittable, "Expected switch \(identifier) to be hittable")
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }

        let deadline = Date().addingTimeInterval(2)
        while target.valueDescription != expectedValue && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertEqual(target.valueDescription, expectedValue, "Expected switch \(identifier) to be \(expectedValue)")
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

    func label(_ identifier: String) -> String {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Expected \(identifier) to exist")
        return target.label
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
    static let startShowInfoButton = "sample.start.show-info"
    static let startInfoText = "sample.start-info.text"
    static let startInfoDismissButton = "sample.start-info.dismiss"
    static let landing = "sample.landing"

    static let homeTab = "sample.tab.home"
    static let settingsTab = "sample.tab.settings"

    static let homeWelcome = "sample.home.welcome"
    static let homeShowMessageButton = "sample.home.show-message"
    static let homeProfileButton = "sample.home.profile"
    static let homeShowDismissProbeButton = "sample.home.show-dismiss-probe"
    static let homePresentHighPriorityPassthroughSheetButton = "sample.home.present-high-priority-passthrough-sheet"
    static let homePresentHighPriorityBlockingSheetButton = "sample.home.present-high-priority-blocking-sheet"
    static let homeShowNavigationBarFadeButton = "sample.home.show-navigation-bar-fade"
    static let homePassthroughBehindButton = "sample.home.passthrough-behind"
    static let homePassthroughTapCount = "sample.home.passthrough-tap-count"
    static let homeRoutePhase = "sample.home.route-phase"
    static let homeEmojiValue = "sample.home.emoji-value"
    static let homeUnwindPayloadStatus = "sample.home.unwind-payload-status"
    static let homeDismissProbeHookStatus = "sample.home.dismiss-probe-hook-status"

    static let settingsAppearanceButton = "sample.settings.appearance"
    static let settingsAuthenticationButton = "sample.settings.authentication"
    static let settingsProfileButton = "sample.settings.profile"
    static let settingsSaveAppearanceButton = "sample.settings.save-appearance"
    static let settingsNewEmojiButton = "sample.settings.new-emoji"
    static let settingsPresentHomeMessageButton = "sample.settings.present-home-message"
    static let settingsPresentDroppedRouteButton = "sample.settings.present-dropped-route"
    static let settingsPresentUndeclaredRouteButton = "sample.settings.present-undeclared-route"
    static let settingsMissingUnwindButton = "sample.settings.missing-unwind"
    static let settingsMissingUnwindResult = "sample.settings.missing-unwind-result"
    static let settingsBranchHookStatus = "sample.settings.branch-hook-status"

    static let appearanceTitle = "sample.appearance.title"
    static let appearanceValue = "sample.appearance.value"
    static let appearanceRePresentButton = "sample.appearance.re-present"
    static let appearanceRePresentDifferentButton = "sample.appearance.re-present-different"
    static let appearancePresentAuthenticationButton = "sample.appearance.present-authentication"
    static let appearanceUnwindToLandingPresentMessageButton = "sample.appearance.unwind-landing-present-message"
    static let appearanceSaveButton = "sample.appearance.save"
    static let appearanceSavedCount = "sample.appearance.saved-count"

    static let authenticationTitle = "sample.authentication.title"
    static let authenticationAttachLocalRouteToggle = "sample.authentication.attach-local-route"
    static let authenticationPresentTopLevelSheetButton = "sample.authentication.present-top-level-sheet"
    static let authenticationPresentTopLevelCoverButton = "sample.authentication.present-top-level-cover"
    static let authenticationUnwindToRootButton = "sample.authentication.unwind-to-root"
    static let authenticationUnwindToNearestBranchButton = "sample.authentication.unwind-to-nearest-branch"
    static let authenticationUnwindToBranchIDButton = "sample.authentication.unwind-to-branch-id"
    static let authenticationUnwindCapturedLandingButton = "sample.authentication.unwind-captured-landing"

    static let topLevelSheetText = "sample.top-level-sheet.text"
    static let topLevelSheetPresentationSource = "sample.top-level-sheet.presentation-source"
    static let topLevelSheetPresentCoverButton = "sample.top-level-sheet.present-cover"
    static let topLevelSheetDismissButton = "sample.top-level-sheet.dismiss"
    static let topLevelCoverText = "sample.top-level-cover.text"
    static let topLevelCoverPresentReplacementButton = "sample.top-level-cover.present-replacement"
    static let topLevelReplacementCoverText = "sample.top-level-replacement-cover.text"
    static let topLevelReplacementCoverDismissButton = "sample.top-level-replacement-cover.dismiss"
    static let highPriorityPassthroughSheetText = "sample.high-priority-passthrough-sheet.text"
    static let highPriorityPassthroughSheetRoutePhase = "sample.high-priority-passthrough-sheet.route-phase"
    static let highPriorityPassthroughSheetDismissButton = "sample.high-priority-passthrough-sheet.dismiss"
    static let highPriorityBlockingSheetText = "sample.high-priority-blocking-sheet.text"
    static let highPriorityBlockingSheetDismissButton = "sample.high-priority-blocking-sheet.dismiss"

    static let messageText = "sample.message.text"
    static let messagePresentationSource = "sample.message.presentation-source"
    static let messageDismissUnwindButton = "sample.message.dismiss-unwind"
    static let messageDismissSwiftUIButton = "sample.message.dismiss-swiftui"
    static let messageDismissPayloadButton = "sample.message.dismiss-payload"
    static let messageDismissMismatchedPayloadButton = "sample.message.dismiss-mismatched-payload"
    static let navigationBarFadeText = "sample.navigation-bar-fade.text"
    static let navigationBarFadeToolbarButton = "sample.navigation-bar-fade.toolbar-button"
    static let navigationBarFadeToolbarTapCount = "sample.navigation-bar-fade.toolbar-tap-count"

    static let dismissProbeText = "sample.dismiss-probe.text"
    static let dismissProbeDismissButton = "sample.dismiss-probe.dismiss"

    static let alertText = "sample.alert.text"
    static let alertDismissUnwindButton = "sample.alert.dismiss-unwind"
    static let alertDismissSwiftUIButton = "sample.alert.dismiss-swiftui"

    static let loginTitle = "sample.login.title"
    static let loginIsPresented = "sample.login.is-presented"
    static let loginWindowEnvironmentValue = "sample.login.window-environment"
    static let loginPresentationProbeCount = "sample.login.presentation-probe-count"
    static let loginIncrementPresentationProbeButton = "sample.login.increment-presentation-probe"
    static let loginToolbarIncrementPresentationProbeButton = "sample.login.toolbar-increment-presentation-probe"
    static let loginButton = "sample.login.button"
    static let loginCancelButton = "sample.login.cancel"
    static let loginReplaceHighPriorityButton = "sample.login.replace-high-priority"
    static let loginPresentAlertButton = "sample.login.present-alert"
    static let loginPresentCriticalButton = "sample.login.present-critical"
    static let loginPushDetailButton = "sample.login.push-detail"
    static let loginPresentHighPrioritySheetButton = "sample.login.present-high-priority-sheet"

    static let loginDetailText = "sample.login-detail.text"
    static let loginDetailPresentLoginButton = "sample.login-detail.present-login"
    static let loginNoticeText = "sample.login-notice.text"
    static let loginNoticeDismissButton = "sample.login-notice.dismiss"

    static let replacementTitle = "sample.replacement.title"
    static let replacementIsPresented = "sample.replacement.is-presented"
    static let replacementWindowEnvironmentValue = "sample.replacement.window-environment"
    static let replacementDismissButton = "sample.replacement.dismiss"
    static let criticalText = "sample.critical.text"
    static let criticalWindowEnvironmentValue = "sample.critical.window-environment"
    static let criticalScenePhaseValue = "sample.critical.scene-phase"
    static let criticalReplaceButton = "sample.critical.replace"
    static let criticalDismissButton = "sample.critical.dismiss"
    static let criticalReplacementText = "sample.critical-replacement.text"
    static let criticalReplacementDismissButton = "sample.critical-replacement.dismiss"

    static let profileTitle = "sample.profile.title"
    static let profileSignOutButton = "sample.profile.sign-out"
    static let profilePresentTopLevelSheetButton = "sample.profile.present-top-level-sheet"

    static let droppedRouteText = "sample.dropped-route.text"
    static let undeclaredRouteText = "sample.undeclared-route.text"
    static let rootHookStatus = "sample.root-hook-status"
    static let landingContainerHookStatus = "sample.landing.container-hook-status"
}
