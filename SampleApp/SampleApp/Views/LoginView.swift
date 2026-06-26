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

struct LoginView: View {
    let nextRoute: (any Route)?

    @Environment(Router.self) private var router
    @Environment(\.sampleWindowBadge) private var sampleWindowBadge
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentationProbeCount = 0

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "Window environment",
                    value: "\(sampleWindowBadge) / \(scenePhase.description)"
                )
                    .accessibilityIdentifier(SampleAppAccessibility.loginWindowEnvironmentValue)

                if SampleAppUITesting.isEnabled {
                    Text("Login presentation probe: \(presentationProbeCount)")
                        .accessibilityIdentifier(SampleAppAccessibility.loginPresentationProbeCount)

                    Button("Increment presentation probe") {
                        presentationProbeCount += 1
                    }
                    .accessibilityIdentifier(SampleAppAccessibility.loginIncrementPresentationProbeButton)
                }
            }

            Section {
                Button("Push detail") {
                    Task {
                        await router.present(LoginDetailRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.loginPushDetailButton)

                Button("Present high-priority sheet") {
                    Task {
                        await router.present(LoginNoticeRoute())
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.loginPresentHighPrioritySheetButton)
            }

            Button("Log in") {
                Storage.shared.isLoggedIn = true
                Task {
                    await router.unwind()

                    if let nextRoute {
                        await router.present(nextRoute)
                    }
                }
            }
            .accessibilityIdentifier(SampleAppAccessibility.loginButton)

            Section {
                Button("Replace with high-priority cover") {
                    Task {
                        await router.present(LoginReplacementRoute())
                    }
                }
                .bold()
                .accessibilityIdentifier(SampleAppAccessibility.loginReplaceHighPriorityButton)

                Text("A second high-priority cover attached to the same scope should replace this login cover.")

                Button("Present alert") {
                    Task {
                        await router.present(AlertRoute())
                    }
                }
                .bold()
                .accessibilityIdentifier(SampleAppAccessibility.loginPresentAlertButton)
                Text("An alert attached to an ancestor scope with high priority should replace this screen.")

                Button("Present critical cover") {
                    Task {
                        await router.present(CriticalRoute())
                    }
                }
                .bold()
                .accessibilityIdentifier(SampleAppAccessibility.loginPresentCriticalButton)
                Text("A critical cover should appear above this high-priority cover without replacing it.")
            }
        }
        .navigationTitle("Login")
        .accessibilityIdentifier(SampleAppAccessibility.loginTitle)
        .routes {
            Push(LoginDetailRoute.self)
            Sheet(LoginNoticeRoute.self, priority: .high, providesNavigation: false)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    Task {
                        await router.unwind()
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.loginCancelButton)
            }
        }
    }
}

struct LoginReplacementView: View {
    @Environment(Router.self) private var router
    @Environment(\.sampleWindowBadge) private var sampleWindowBadge
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "Window environment",
                    value: "\(sampleWindowBadge) / \(scenePhase.description)"
                )
                    .accessibilityIdentifier(SampleAppAccessibility.replacementWindowEnvironmentValue)
            }

            Text("This high-priority cover replaced the login high-priority cover.")

            Button("Dismiss replacement") {
                Task {
                    await router.unwind()
                }
            }
            .bold()
            .accessibilityIdentifier(SampleAppAccessibility.replacementDismissButton)
        }
        .navigationTitle("Replacement")
        .accessibilityIdentifier(SampleAppAccessibility.replacementTitle)
    }
}

struct CriticalView: View {
    @Environment(Router.self) private var router
    @Environment(\.sampleWindowBadge) private var sampleWindowBadge
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 16) {
            Text("Critical route")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.criticalText)

            LabeledContent("Window environment", value: sampleWindowBadge)
                .accessibilityIdentifier(SampleAppAccessibility.criticalWindowEnvironmentValue)

            LabeledContent("Scene phase", value: scenePhase.description)
                .accessibilityIdentifier(SampleAppAccessibility.criticalScenePhaseValue)

            Button("Replace critical") {
                Task {
                    await router.present(CriticalReplacementRoute())
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.criticalReplaceButton)

            Button("Dismiss critical") {
                Task {
                    await router.unwind()
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(SampleAppAccessibility.criticalDismissButton)
        }
        .padding()
        .background {
            Color.white
        }
    }
}

struct CriticalReplacementView: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            Text("Critical replacement")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.criticalReplacementText)

            Button("Dismiss critical replacement") {
                Task {
                    await router.unwind()
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.criticalReplacementDismissButton)
        }
        .padding()
        .background {
            Color.red
        }
        .padding()
    }
}

private extension ScenePhase {
    var description: String {
        switch self {
        case .active:
            "active"

        case .inactive:
            "inactive"

        case .background:
            "background"

        @unknown default:
            "unknown"
        }
    }
}

struct LoginDetailView: View {
    @Environment(Router.self) private var router

    var body: some View {
        List {
            Text("Pushed from the login screen.")
                .accessibilityIdentifier(SampleAppAccessibility.loginDetailText)

            if SampleAppUITesting.isEnabled {
                Button("Present login again") {
                    Task {
                        await router.present(LoginRoute(nextRoute: nil))
                    }
                }
                .accessibilityIdentifier(SampleAppAccessibility.loginDetailPresentLoginButton)
            }
        }
        .navigationTitle("Login detail")
    }
}

struct LoginNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Login notice")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.loginNoticeText)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.loginNoticeDismissButton)
        }
        .padding()
    }
}
