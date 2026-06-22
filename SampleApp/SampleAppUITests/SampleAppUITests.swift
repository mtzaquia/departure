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

    func testTopLevelSheetCanPresentFromPushedAuthenticationSettings() {
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

        tap(A11y.topLevelSheetDismissButton)
        assertGone(A11y.topLevelSheetText)
        assertExists(A11y.authenticationTitle)
    }

    func testTopLevelCoverReplacementPreservesPushedBranchStackAndShowsReplacementContent() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tap(A11y.authenticationPresentTopLevelCoverButton)
        assertExists(A11y.topLevelCoverText)

        tap(A11y.topLevelCoverPresentReplacementButton)
        assertExists(A11y.topLevelReplacementCoverText)
        assertGone(A11y.topLevelCoverText)

        tap(A11y.topLevelReplacementCoverDismissButton)
        assertGone(A11y.topLevelReplacementCoverText)
        assertExists(A11y.authenticationTitle)
        assertGone(A11y.settingsAuthenticationButton)
    }

    func testAncestorCoverReplacementFromDescendantLocalSheetDismissesSheetAndPreservesPushStack() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsAuthenticationButton)
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

    func testTopLevelSheetPresentedFromBranchLocalProfileSheetDismissesItAndPresentsTopLevel() {
        openLanding()

        // Present the home-branch-local Profile sheet (reroutes through login first).
        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)

        tap(A11y.loginButton)
        assertExists(A11y.profileTitle)

        // Presenting the top-level sheet from within the branch-local sheet must dismiss the
        // branch-local Profile sheet and present the top-level sheet from the branched scope.
        tap(A11y.profilePresentTopLevelSheetButton)
        assertExists(A11y.topLevelSheetText)
        assertLabel(A11y.topLevelSheetPresentationSource, contains: "top-level branched scope")
        assertGone(A11y.profileTitle)

        // Dismissing the top-level sheet returns to home — the branch-local Profile sheet was
        // dismissed, not merely covered, so it must not re-appear.
        tap(A11y.topLevelSheetDismissButton)
        assertGone(A11y.topLevelSheetText)
        assertGone(A11y.profileTitle)
        assertExists(A11y.homeWelcome)
    }

    func testInactiveBranchPushIsPreservedWhenSwitchingTabs() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tapHomeTab()
        assertExists(A11y.homeWelcome)

        tapSettingsTab()
        assertExists(A11y.authenticationTitle)
        assertGone(A11y.settingsAuthenticationButton)

        tapHomeTab()
        assertExists(A11y.homeWelcome)

        tapSettingsTab()
        assertExists(A11y.authenticationTitle)
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

    func testRoutesFromHighPriorityContextBehaveAsNormalNavigationAndModal() {
        openLanding()

        // Reaching profile while logged out reroutes to the login high-priority cover, starting a
        // high-priority context.
        tap(A11y.homeProfileButton)
        assertExists(A11y.loginTitle)

        // A high-priority sheet declared inside the context presents as a normal sheet over login
        // — it must not escalate/replace the login cover, so login stays in the hierarchy behind it.
        tap(A11y.loginPresentHighPrioritySheetButton)
        assertExists(A11y.loginNoticeText)
        assertExists(A11y.loginTitle)

        tap(A11y.loginNoticeDismissButton)
        assertGone(A11y.loginNoticeText)
        assertExists(A11y.loginTitle)

        // A normal push declared inside the context navigates within the login stack (it is not
        // blocked the way a normal route before the context would be).
        tap(A11y.loginPushDetailButton)
        assertExists(A11y.loginDetailText)
    }

    func testUnwindToRootFromDeepWithinSettingsBranchCrossesBranchedScope() {
        openLanding()
        tapSettingsTab()

        // Go deep: a pushed route inside the settings branch stack.
        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        // Unwind to root (the app start) from deep inside the branch. This crosses the settings
        // branch scope and the branched landing scope (resolved via the ancestor unwind path).
        tap(A11y.authenticationUnwindToRootButton)
        assertExists(A11y.startButton)
        assertGone(A11y.authenticationTitle)
        assertGone(A11y.landing)

        // The root scope survived the cross-branch unwind: its sheet still presents and dismisses.
        tap(A11y.startShowInfoButton)
        assertExists(A11y.startInfoText)

        tap(A11y.startInfoDismissButton)
        assertGone(A11y.startInfoText)
        assertExists(A11y.startButton)
    }

    func testUnwindHookPayloadDeliveryAndMismatch() {
        openLanding()

        assertLabel(A11y.homeUnwindPayloadStatus, contains: "Payload hooks:")

        tap(A11y.homeShowMessageButton)
        assertExists(A11y.messageText)

        tap(A11y.messageDismissPayloadButton)
        assertGone(A11y.messageText)
        assertLabel(A11y.homeUnwindPayloadStatus, contains: "message delivered")

        tap(A11y.homeShowMessageButton)
        assertExists(A11y.messageText)

        tap(A11y.messageDismissMismatchedPayloadButton)
        assertGone(A11y.messageText)
        assertLabel(A11y.homeUnwindPayloadStatus, contains: "message delivered")
    }

    func testSwiftUIDismissTriggersUnwindHandlerThatCanPresentRoute() {
        openLanding()

        tap(A11y.homeShowDismissProbeButton)
        assertExists(A11y.dismissProbeText)

        tap(A11y.dismissProbeDismissButton)
        assertGone(A11y.dismissProbeText)
        assertExists(A11y.messageText)

        tap(A11y.messageDismissUnwindButton)
        assertGone(A11y.messageText)
        assertLabel(A11y.homeDismissProbeHookStatus, contains: "Dismiss probe hooks: 1")
    }

    func testUnwindHooksFireForRootNearestBranchAndExplicitBranchIDTargets() {
        openLanding()
        tapSettingsTab()

        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        tap(A11y.authenticationUnwindToNearestBranchButton)
        assertGone(A11y.authenticationTitle)
        assertExists(A11y.settingsAuthenticationButton)
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
    }

    func testUnwindToNearestBranchReturnsToBranchRootAndIsIdempotentThere() {
        openLanding()
        tapSettingsTab()

        // Go deep: a pushed route inside the settings branch stack.
        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)

        // Unwind to the nearest branch: pops back to the settings branch root, NOT all the way to
        // the app start. The landing (tabbed) container stays mounted — proving we did not escape
        // the branch (a full unwind would dismiss `landing`, see the `.root` test above).
        tap(A11y.authenticationUnwindToNearestBranchButton)
        assertGone(A11y.authenticationTitle)
        assertExists(A11y.settingsAuthenticationButton)
        assertExists(A11y.landing)

        // Already at the branch root: pushing in again and unwinding lands back at the same place,
        // and the engine never escapes the branch to the app start.
        tap(A11y.settingsAuthenticationButton)
        assertExists(A11y.authenticationTitle)
        tap(A11y.authenticationUnwindToNearestBranchButton)
        assertGone(A11y.authenticationTitle)
        assertExists(A11y.settingsAuthenticationButton)
        assertExists(A11y.landing)
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
    static let appearanceRePresentButton = "sample.appearance.re-present"
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

    static let topLevelSheetText = "sample.top-level-sheet.text"
    static let topLevelSheetPresentationSource = "sample.top-level-sheet.presentation-source"
    static let topLevelSheetPresentCoverButton = "sample.top-level-sheet.present-cover"
    static let topLevelSheetDismissButton = "sample.top-level-sheet.dismiss"
    static let topLevelCoverText = "sample.top-level-cover.text"
    static let topLevelCoverPresentReplacementButton = "sample.top-level-cover.present-replacement"
    static let topLevelReplacementCoverText = "sample.top-level-replacement-cover.text"
    static let topLevelReplacementCoverDismissButton = "sample.top-level-replacement-cover.dismiss"

    static let messageText = "sample.message.text"
    static let messageDismissUnwindButton = "sample.message.dismiss-unwind"
    static let messageDismissSwiftUIButton = "sample.message.dismiss-swiftui"
    static let messageDismissPayloadButton = "sample.message.dismiss-payload"
    static let messageDismissMismatchedPayloadButton = "sample.message.dismiss-mismatched-payload"

    static let dismissProbeText = "sample.dismiss-probe.text"
    static let dismissProbeDismissButton = "sample.dismiss-probe.dismiss"

    static let alertText = "sample.alert.text"
    static let alertDismissUnwindButton = "sample.alert.dismiss-unwind"
    static let alertDismissSwiftUIButton = "sample.alert.dismiss-swiftui"

    static let loginTitle = "sample.login.title"
    static let loginWindowEnvironmentValue = "sample.login.window-environment"
    static let loginButton = "sample.login.button"
    static let loginReplaceHighPriorityButton = "sample.login.replace-high-priority"
    static let loginPresentAlertButton = "sample.login.present-alert"
    static let loginPushDetailButton = "sample.login.push-detail"
    static let loginPresentHighPrioritySheetButton = "sample.login.present-high-priority-sheet"

    static let loginDetailText = "sample.login-detail.text"
    static let loginNoticeText = "sample.login-notice.text"
    static let loginNoticeDismissButton = "sample.login-notice.dismiss"

    static let replacementTitle = "sample.replacement.title"
    static let replacementWindowEnvironmentValue = "sample.replacement.window-environment"
    static let replacementDismissButton = "sample.replacement.dismiss"

    static let profileTitle = "sample.profile.title"
    static let profileSignOutButton = "sample.profile.sign-out"
    static let profilePresentTopLevelSheetButton = "sample.profile.present-top-level-sheet"

    static let droppedRouteText = "sample.dropped-route.text"
    static let undeclaredRouteText = "sample.undeclared-route.text"
    static let rootHookStatus = "sample.root-hook-status"
    static let landingContainerHookStatus = "sample.landing.container-hook-status"
}
