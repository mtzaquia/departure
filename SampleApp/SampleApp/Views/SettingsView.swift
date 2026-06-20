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

struct SettingsView: View {
    @Environment(Router.self) private var router
    @State private var storage = Storage.shared

    var body: some View {
        List {
            Button("Appearance") {
                Task {
                    await router.present(AppearanceSettingsRoute())
                }
            }
            .accessibilityIdentifier(SampleAppAccessibility.settingsAppearanceButton)

            Button("Authentication") {
                Task {
                    await router.present(AuthenticationSettingsRoute())
                }
            }
            .accessibilityIdentifier(SampleAppAccessibility.settingsAuthenticationButton)

            Button("Profile") {
                Task {
                    await router.present(ProfileRoute())
                }
            }
            .accessibilityIdentifier(SampleAppAccessibility.settingsProfileButton)

            Section("Actions") {
                Button("Save appearance") {
                    Task {
                        await router.perform(SaveAppearanceSettingsAction())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.settingsSaveAppearanceButton)

                Button("New emoji") {
                    Task {
                        await router.perform(RandomizeEmojiAction())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.settingsNewEmojiButton)
            }

            if SampleAppUITesting.isEnabled {
                Section("UI Tests") {
                    Text("Container unwind hooks: \(storage.landingContainerUnwindHookCount)")
                        .accessibilityIdentifier(SampleAppAccessibility.landingContainerHookStatus)

                    Text("Branch unwind hooks: \(storage.settingsBranchUnwindHookCount)")
                        .accessibilityIdentifier(SampleAppAccessibility.settingsBranchHookStatus)

                    Button("Present home message") {
                        Task {
                            await router.present(MessageRoute())
                        }
                    }
                    .accessibilityIdentifier(SampleAppAccessibility.settingsPresentHomeMessageButton)

                    Button("Present dropped route") {
                        Task {
                            await router.present(DroppedRoute())
                        }
                    }
                    .accessibilityIdentifier(SampleAppAccessibility.settingsPresentDroppedRouteButton)

                    Button("Present undeclared route") {
                        Task {
                            await router.present(UndeclaredRoute())
                        }
                    }
                    .accessibilityIdentifier(SampleAppAccessibility.settingsPresentUndeclaredRouteButton)

                    Button("Attempt missing unwind") {
                        Task {
                            storage.missingUnwindResult = await router.unwind(to: .id("missing"))
                        }
                    }
                    .accessibilityIdentifier(SampleAppAccessibility.settingsMissingUnwindButton)

                    Text("Missing unwind: \(storage.missingUnwindResult.map(String.init) ?? "none")")
                        .accessibilityIdentifier(SampleAppAccessibility.settingsMissingUnwindResult)
                }
            }
        }
        .navigationTitle("Settings")
        .hooks {
            UnwindHandler(AuthenticationSettingsRoute.self) {
                guard SampleAppUITesting.isEnabled else {
                    return
                }

                Storage.shared.settingsBranchUnwindHookCount += 1
            }
        }
    }
}
