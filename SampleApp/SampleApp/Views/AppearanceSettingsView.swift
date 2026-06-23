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

struct AppearanceSettingsView: View {
    @State private var storage = Storage.shared
    @Environment(Router.self) private var router

    var body: some View {
        List {
            Section {
                Button("Re-present this") {
                    Task {
                        await router.present(AppearanceSettingsRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.appearanceRePresentButton)

                Button("Present authentication settings") {
                    Task {
                        await router.present(AuthenticationSettingsRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.appearancePresentAuthenticationButton)

                if SampleAppUITesting.isEnabled {
                    Button("Unwind to landing, present home message") {
                        Task {
                            guard await router.unwind(to: .id(LandingRoute().id)) else {
                                return
                            }

                            await router.present(MessageRoute())
                        }
                    }
                    .accessibilityIdentifier(SampleAppAccessibility.appearanceUnwindToLandingPresentMessageButton)
                }
            }

            Section("Actions") {
                Button("Save appearance") {
                    Task {
                        await router.perform(SaveAppearanceSettingsAction())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.appearanceSaveButton)

                Text("Saved \(storage.appearanceSaveCount) time(s)")
                    .accessibilityIdentifier(SampleAppAccessibility.appearanceSavedCount)
            }
        }
        .navigationTitle("Appearance")
        .accessibilityIdentifier(SampleAppAccessibility.appearanceTitle)
        .routes {
            Push(AuthenticationSettingsRoute.self)
        }
        .hooks {
            ActionInterceptor(SaveAppearanceSettingsAction.self) { invocation in
                try? await invocation()
            }
        }
    }
}
