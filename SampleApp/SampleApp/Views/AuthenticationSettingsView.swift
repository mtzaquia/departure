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

struct AuthenticationSettingsView: View {
    @Environment(Router.self) private var router

    let state: AuthenticationSettingsRouteState

    var body: some View {
        List {
            Toggle(
                "Logged in",
                isOn: .init(
                    get: { Storage.shared.isLoggedIn },
                    set: { Storage.shared.isLoggedIn = $0 }
                )
            )
            .accessibilityIdentifier(SampleAppAccessibility.authenticationLoggedInToggle)

            Section("Sheet") {
                Toggle(
                    "Attach local route",
                    isOn: .init(
                        get: { state.attachesLocalRoute },
                        set: { state.attachesLocalRoute = $0 }
                    )
                )
                .accessibilityIdentifier(SampleAppAccessibility.authenticationAttachLocalRouteToggle)

                Button("Present top-level sheet") {
                    Task {
                        await router.present(TopLevelSheetRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.authenticationPresentTopLevelSheetButton)

                Button("Present top-level cover") {
                    Task {
                        await router.present(TopLevelCoverRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.authenticationPresentTopLevelCoverButton)

                Button("Present info from Start") {
                    Task {
                        await router.present(StartInfoRoute())
                    }
                }

                Button("Unwind to root") {
                    Task {
                        await router.unwind(to: .root)
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.authenticationUnwindToRootButton)

                Button("Unwind to nearest branch") {
                    Task {
                        await router.unwind(to: .nearestBranch)
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.authenticationUnwindToNearestBranchButton)

                if SampleAppUITesting.isEnabled {
                    Button("Unwind to branch ID") {
                        Task {
                            await router.unwind(to: .id(LandingView.TabItem.settings))
                        }
                    }
                    .accessibilityIdentifier(SampleAppAccessibility.authenticationUnwindToBranchIDButton)

                    Button("Unwind captured Landing route") {
                        Task {
                            await Storage.shared.landingUnwindRoute()
                        }
                    }
                    .accessibilityIdentifier(SampleAppAccessibility.authenticationUnwindCapturedLandingButton)
                }
            }
        }
        .navigationTitle("Authentication")
        .accessibilityIdentifier(SampleAppAccessibility.authenticationTitle)
        .routes {
            if state.attachesLocalRoute {
                Sheet(TopLevelSheetRoute.self, providesNavigation: false)
            }
        }
        .environment(\.samplePresentationSource, "authentication settings scope")
    }
}
