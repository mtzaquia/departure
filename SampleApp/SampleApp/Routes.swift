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

struct LandingRoute: Route {
    func destination() -> some View {
        LandingView()
    }
}

struct StartInfoRoute: Route {
    func destination() -> some View {
        StartInfoView()
    }
}

struct LoginRoute: Route {
    let nextRoute: (any Route)?

    func destination() -> some View {
        LoginView(nextRoute: nextRoute)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }
}

struct LoginReplacementRoute: Route {
    func destination() -> some View {
        LoginReplacementView()
    }
}

struct LoginDetailRoute: Route {
    func destination() -> some View {
        LoginDetailView()
    }
}

struct LoginNoticeRoute: Route {
    func destination() -> some View {
        LoginNoticeView()
    }
}

struct ProfileRoute: Route {
    func resolveRoute() async -> RouteResolution {
        Storage.shared.isLoggedIn ? .allow : .reroute(LoginRoute(nextRoute: ProfileRoute()))
    }

    func destination() -> some View {
        ProfileView()
    }
}

@Observable
final class AuthenticationSettingsRouteState: Equatable {
    var attachesLocalRoute = false

    static func == (lhs: AuthenticationSettingsRouteState, rhs: AuthenticationSettingsRouteState) -> Bool {
        lhs.attachesLocalRoute == rhs.attachesLocalRoute
    }
}

struct AuthenticationSettingsRoute: Route {
    let state: AuthenticationSettingsRouteState

    init(state: AuthenticationSettingsRouteState = AuthenticationSettingsRouteState()) {
        self.state = state
    }

    func destination() -> some View {
        AuthenticationSettingsView(state: state)
    }
}

struct TopLevelSheetRoute: Route {
    func destination() -> some View {
        TopLevelSheetView()
    }
}

struct TopLevelCoverRoute: Route {
    func destination() -> some View {
        TopLevelCoverView()
    }
}

struct TopLevelReplacementCoverRoute: Route {
    func destination() -> some View {
        TopLevelReplacementCoverView()
    }
}

struct HighPriorityPassthroughSheetRoute: Route {
    func destination() -> some View {
        HighPriorityPassthroughSheetView()
    }
}

struct HighPriorityBlockingSheetRoute: Route {
    func destination() -> some View {
        HighPriorityBlockingSheetView()
    }
}

struct NavigationBarFadeOcclusionRoute: Route {
    func destination() -> some View {
        NavigationBarFadeOcclusionView()
    }
}

struct TopLevelSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.samplePresentationSource) private var samplePresentationSource
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            Text("Top-level sheet")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetText)

            Text("Presented from: \(samplePresentationSource)")
                .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetPresentationSource)

            Button("Present cover") {
                Task {
                    await router.present(TopLevelCoverRoute())
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetPresentCoverButton)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetDismissButton)
        }
        .padding()
    }
}

struct TopLevelCoverView: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            Text("Top-level cover")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.topLevelCoverText)

            Button("Present replacement cover") {
                Task {
                    await router.present(TopLevelReplacementCoverRoute())
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.topLevelCoverPresentReplacementButton)
        }
        .padding()
    }
}

struct TopLevelReplacementCoverView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Top-level replacement cover")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.topLevelReplacementCoverText)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.topLevelReplacementCoverDismissButton)
        }
        .padding()
    }
}

struct HighPriorityPassthroughSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.routePhase) private var routePhase

    var body: some View {
        VStack(spacing: 16) {
            Text("High-priority passthrough sheet")
                .font(.headline)
                .accessibilityLabel(presentationLabel("High-priority passthrough sheet"))
                .accessibilityIdentifier(SampleAppAccessibility.highPriorityPassthroughSheetText)

            Text("Route phase: \(routePhaseLabel)")
                .accessibilityIdentifier(SampleAppAccessibility.highPriorityPassthroughSheetRoutePhase)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.highPriorityPassthroughSheetDismissButton)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .presentationDetents([.height(220)])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(220)))
        .samplePresentationSizing()
    }

    private var routePhaseLabel: String {
        switch routePhase {
        case .active:
            return "active"

        case .inactive:
            return "inactive"
        }
    }

    private func presentationLabel(_ label: String) -> String {
        guard SampleAppUITesting.isEnabled else {
            return label
        }

        return label + " SwiftUI isPresented: " + String(isPresented)
    }
}

struct HighPriorityBlockingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        VStack(spacing: 16) {
            Text("High-priority blocking sheet")
                .font(.headline)
                .accessibilityLabel(presentationLabel("High-priority blocking sheet"))
                .accessibilityIdentifier(SampleAppAccessibility.highPriorityBlockingSheetText)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.highPriorityBlockingSheetDismissButton)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .presentationDetents([.height(220)])
        .samplePresentationSizing()
    }

    private func presentationLabel(_ label: String) -> String {
        guard SampleAppUITesting.isEnabled else {
            return label
        }

        return label + " SwiftUI isPresented: " + String(isPresented)
    }
}

struct NavigationBarFadeOcclusionView: View {
    @Environment(Router.self) private var router
    @State private var toolbarTapCount = 0

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            List {
                Text("Navigation bar fade probe")
                    .accessibilityIdentifier(SampleAppAccessibility.navigationBarFadeText)

                Text("Toolbar taps: \(toolbarTapCount)")
                    .accessibilityIdentifier(SampleAppAccessibility.navigationBarFadeToolbarTapCount)

            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Fade Chrome")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Tap toolbar") {
                    toolbarTapCount += 1
                }
                .accessibilityIdentifier(SampleAppAccessibility.navigationBarFadeToolbarButton)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func samplePresentationSizing() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.fitted)
        } else {
            self
        }
    }
}

struct AppearanceSettingsRoute: Route, Equatable {
    let value: UUID?

    func destination() -> some View {
        AppearanceSettingsView(value: value)
    }
}

struct AlertRoute: Route {
    func destination() -> some View {
        AlertView()
    }
}

struct CriticalRoute: Route {
    func destination() -> some View {
        CriticalView()
    }
}

struct CriticalReplacementRoute: Route {
    func destination() -> some View {
        CriticalReplacementView()
    }
}

struct MessageRoute: Route {
    func destination() -> some View {
        MessageView()
    }
}

struct DismissProbeRoute: Route {
    func destination() -> some View {
        DismissProbeView()
    }
}

struct DismissProbeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Dismiss probe")
                .font(.headline)
                .accessibilityIdentifier(SampleAppAccessibility.dismissProbeText)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(SampleAppAccessibility.dismissProbeDismissButton)
        }
        .padding()
    }
}

struct DroppedRoute: Route {
    func resolveRoute() async -> RouteResolution {
        .drop
    }

    func destination() -> some View {
        Text("Dropped route should not appear.")
            .accessibilityIdentifier(SampleAppAccessibility.droppedRouteText)
    }
}

struct UndeclaredRoute: Route {
    func destination() -> some View {
        Text("Undeclared route should not appear.")
            .accessibilityIdentifier(SampleAppAccessibility.undeclaredRouteText)
    }
}
