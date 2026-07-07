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

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum SampleAppUITesting {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("UI_TESTING")

    @MainActor
    static func configure() {
        guard isEnabled else {
            return
        }

        Storage.shared.reset()

        #if canImport(UIKit)
        UIView.setAnimationsEnabled(false)
        #endif
    }
}

enum SampleAppAccessibility {
    static let startButton = "sample.start.button"
    static let startShowInfoButton = "sample.start.show-info"
    static let startScopeID = "sample.start.scope"
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
    static let authenticationLoggedInToggle = "sample.authentication.logged-in"
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
    static let loginEmailField = "sample.login.email"
    static let loginPasswordField = "sample.login.password"
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
