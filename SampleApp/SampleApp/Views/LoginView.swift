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

    @Environment(\.router) private var router
    @Environment(\.isPresented) private var isPresented
    @Environment(\.sampleWindowBadge) private var sampleWindowBadge
    @Environment(\.scenePhase) private var scenePhase
    @UnwindRoute private var unwindRoute
    @State private var presentationProbeCount = 0

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        LabScreen("Shared authentication", eyebrow: "Global cover", symbol: "lock.shield.fill") {
            Text("Login route active")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.loginTitle)

            LabPanel("Presentation environment") {
                LabStatus(label: "Presentation", value: "SwiftUI isPresented: \(String(isPresented))", symbol: "rectangle.on.rectangle.circle.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.loginIsPresented)
                LabStatus(label: "Inherited environment", value: "\(sampleWindowBadge) / \(scenePhase.description)", color: LabPalette.blue, symbol: "arrowshape.turn.up.forward.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.loginWindowEnvironmentValue)
                LabStatus(label: "Interaction probe", value: "Login presentation probe: \(presentationProbeCount)", color: LabPalette.amber, symbol: "hand.tap.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.loginPresentationProbeCount)
            }

            LabPanel("Routes inside the global flow") {
                LazyVGrid(columns: columns, spacing: 8) {
                    action("Increment probe", symbol: "plus.circle.fill", color: LabPalette.amber, id: SampleAppAccessibility.loginIncrementPresentationProbeButton) { presentationProbeCount += 1 }
                    action("Push detail", symbol: "arrow.right.square.fill", id: SampleAppAccessibility.loginPushDetailButton) { Task { await router.present(LoginDetailRoute()) } }
                    action("Local sheet", symbol: "rectangle.bottomhalf.inset.filled", color: LabPalette.blue, id: SampleAppAccessibility.loginPresentLocalSheetButton) { Task { await router.present(LoginNoticeRoute()) } }
                    action("Present another global", symbol: "arrow.triangle.2.circlepath", color: LabPalette.coral, id: SampleAppAccessibility.loginPresentGlobalButton) { Task { await router.present(LoginReplacementRoute()) } }
                    action("Global alert", symbol: "exclamationmark.bubble.fill", color: LabPalette.coral, id: SampleAppAccessibility.loginPresentAlertButton) { Task { await router.present(AlertRoute()) } }
                    action("Passcode lock", symbol: "exclamationmark.triangle.fill", color: LabPalette.amber, id: SampleAppAccessibility.loginPresentPasscodeButton) { Task { await router.present(PasscodeRoute()) } }
                }
            }

            HStack {
                Button("Cancel", systemImage: "xmark") {
                    Task { await unwindRoute() }
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .accessibilityIdentifier(SampleAppAccessibility.loginCancelButton)

                Button("Log in and continue", systemImage: "person.badge.key.fill") {
                    Storage.shared.isLoggedIn = true
                    Task {
                        let continuation = Storage.shared.landingRouter ?? router
                        await unwindRoute()
                        if let nextRoute {
                            await SampleDeepLink.router(for: nextRoute, from: continuation).present(nextRoute)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .controlSize(.large)
                .labPrimaryButton(color: LabPalette.mint)
                .accessibilityIdentifier(SampleAppAccessibility.loginButton)
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("Login")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Probe", systemImage: "hand.tap") { presentationProbeCount += 1 }
                    .accessibilityIdentifier(SampleAppAccessibility.loginToolbarIncrementPresentationProbeButton)
            }
        }
    }

    private func action(
        _ title: String,
        symbol: String,
        color: Color = LabPalette.indigo,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        LabAction(title: title, symbol: symbol, color: color, action: action)
            .accessibilityIdentifier(id)
    }
}

struct LoginReplacementView: View {
    @Environment(\.isPresented) private var isPresented
    @Environment(\.sampleWindowBadge) private var sampleWindowBadge
    @Environment(\.scenePhase) private var scenePhase
    @UnwindRoute private var unwindRoute

    var body: some View {
        LabScreen("Replacement cover", eyebrow: "Another global", symbol: "arrow.triangle.2.circlepath") {
            Text("Replacement route active")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.replacementTitle)

            LabPanel("Replacement telemetry") {
                LabStatus(label: "Presentation", value: "SwiftUI isPresented: \(String(isPresented))", symbol: "checkmark.circle.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.replacementIsPresented)
                LabStatus(label: "Inherited environment", value: "\(sampleWindowBadge) / \(scenePhase.description)", color: LabPalette.blue, symbol: "arrowshape.turn.up.forward.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.replacementWindowEnvironmentValue)
            }

            Text("This global cover presents above login and returns to it when dismissed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Dismiss replacement") { Task { await unwindRoute() } }
                .frame(maxWidth: .infinity)
                .labPrimaryButton(color: LabPalette.coral)
                .accessibilityIdentifier(SampleAppAccessibility.replacementDismissButton)

            Spacer()
        }
        .navigationTitle("Replacement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PasscodeView: View {
    @Environment(\.router) private var router
    @Environment(\.isPresented) private var isPresented
    @Environment(\.sampleWindowBadge) private var sampleWindowBadge
    @Environment(\.scenePhase) private var scenePhase
    @UnwindRoute private var unwindRoute

    var body: some View {
        LabModalCard("Passcode lock", subtitle: "Dismissal protection applies while this route is active.", symbol: "exclamationmark.triangle.fill", color: LabPalette.coral) {
            Text("SwiftUI isPresented: \(String(isPresented))")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.passcodeText)
            LabStatus(label: "Window environment", value: sampleWindowBadge, color: LabPalette.blue, symbol: "window.ceiling")
                .accessibilityIdentifier(SampleAppAccessibility.passcodeWindowEnvironmentValue)
            LabStatus(label: "Scene phase", value: scenePhase.description, color: LabPalette.mint, symbol: "circle.fill")
                .accessibilityIdentifier(SampleAppAccessibility.passcodeScenePhaseValue)
            HStack {
                Button("Dismiss") { Task { await unwindRoute() } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(SampleAppAccessibility.passcodeDismissButton)
                Button("Replace") { Task { await router.present(PasscodeOverlayRoute()) } }
                    .labPrimaryButton(color: LabPalette.coral)
                    .accessibilityIdentifier(SampleAppAccessibility.passcodePresentOverlayButton)
            }
        }
    }
}

struct PasscodeOverlayView: View {
    @Environment(\.isPresented) private var isPresented
    @UnwindRoute private var unwindRoute

    var body: some View {
        LabModalCard("Unprotected overlay", subtitle: "The passcode underneath is inactive and its protection is suspended.", symbol: "bolt.shield.fill", color: LabPalette.coral) {
            Text("SwiftUI isPresented: \(String(isPresented))")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.passcodeOverlayText)
            Button("Dismiss overlay") { Task { await unwindRoute() } }
                .labPrimaryButton(color: LabPalette.coral)
                .accessibilityIdentifier(SampleAppAccessibility.passcodeOverlayDismissButton)
        }
    }
}

private extension ScenePhase {
    var description: String {
        switch self {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}

struct LoginDetailView: View {
    @Environment(\.router) private var router
    @UnwindRoute(.nearestModal) private var unwindLogin

    var body: some View {
        LabScreen("Local push", eyebrow: "Inside a global flow", symbol: "arrow.right.square.fill") {
            LabPanel {
                Text("Pushed from the login screen.")
                    .font(.headline)
                    .accessibilityIdentifier(SampleAppAccessibility.loginDetailText)
                Text("This is ordinary navigation inside the global route's child map.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Present global login again") { Task { await router.present(LoginRoute(nextRoute: nil)) } }
                    .labPrimaryButton()
                    .accessibilityIdentifier(SampleAppAccessibility.loginDetailPresentLoginButton)
                Button("Dismiss login flow") { Task { await unwindLogin() } }
                    .labPrimaryButton(color: LabPalette.blue)
                    .accessibilityIdentifier(SampleAppAccessibility.loginDetailDismissFlowButton)
            }
            Spacer()
        }
        .navigationTitle("Login detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LoginNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        LabModalCard("Login notice", subtitle: "A global declaration behaves as a local sheet inside the global tree.", symbol: "rectangle.bottomhalf.inset.filled", color: LabPalette.blue) {
            Text("SwiftUI isPresented: \(String(isPresented))")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.loginNoticeText)
            Button("Dismiss") { dismiss() }
                .labPrimaryButton(color: LabPalette.blue)
                .accessibilityIdentifier(SampleAppAccessibility.loginNoticeDismissButton)
        }
    }
}
