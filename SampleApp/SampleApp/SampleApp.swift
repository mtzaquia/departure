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

import Departure
import SwiftUI

@Observable
final class Storage {
    static let shared = Storage()

    var isLoggedIn = false
    var appearanceSaveCount = 0
    var emoji: String = "🎉"
    var missingUnwindResult: Bool?
    var homeUnwindPayloads: [String] = []
    var rootUnwindHookCount = 0
    var landingContainerUnwindHookCount = 0
    var settingsBranchUnwindHookCount = 0

    func reset() {
        isLoggedIn = false
        appearanceSaveCount = 0
        emoji = "🎉"
        missingUnwindResult = nil
        homeUnwindPayloads = []
        rootUnwindHookCount = 0
        landingContainerUnwindHookCount = 0
        settingsBranchUnwindHookCount = 0
    }
}

struct RandomizeEmojiAction: Action {
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        if SampleAppUITesting.isEnabled {
            Storage.shared.emoji = "⚡️"
            return
        }

        Storage.shared.emoji = ["⚡️", "🎸", "✈️", "🇮🇹", "🎉", "👀"].randomElement() ?? ""
    }
}


struct SaveAppearanceSettingsAction: Action {
    func attemptAction(in context: ActionContext) async throws(ActionInvocationError) {
        guard context.isRunning(in: AppearanceSettingsRoute.self) else {
            throw .reroute(AppearanceSettingsRoute())
        }

        Storage.shared.appearanceSaveCount += 1
    }
}

extension EnvironmentValues {
    @Entry var sampleWindowBadge: String = "not forwarded"
    @Entry var samplePresentationSource: String = "unknown"
}

@main
struct DepartureSampleApp: App {
    init() {
        Departure.debug = true
        SampleAppUITesting.configure()
    }

    var body: some Scene {
        WindowGroup {
            WithRouter {
                NavigationStack {
                    StartView()
                }
                .environment(\.sampleWindowBadge, "forwarded from app window")
            } windowDestination: { destination, environment in
                destination
                    .environment(\.sampleWindowBadge, environment.sampleWindowBadge)
            }
            .transaction { transaction in
                guard SampleAppUITesting.isEnabled else {
                    return
                }

                transaction.animation = nil
            }
        }
    }
}
