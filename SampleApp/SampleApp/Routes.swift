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

struct LandingRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        LandingView()
    }
}

struct StartInfoRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        StartInfoView()
    }
}

struct LoginRoute: SampleDeepLinkRoute, Equatable {
    let nextRoute: (any Route)?

    func destination() -> some View {
        LoginView(nextRoute: nextRoute)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }
}

struct LoginReplacementRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        LoginReplacementView()
    }
}

struct LoginDetailRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        LoginDetailView()
    }
}

struct LoginNoticeRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        LoginNoticeView()
    }
}

struct ProfileRoute: SampleDeepLinkRoute {
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

struct AuthenticationSettingsRoute: SampleDeepLinkRoute {
    let state: AuthenticationSettingsRouteState

    init(state: AuthenticationSettingsRouteState = AuthenticationSettingsRouteState()) {
        self.state = state
    }

    func destination() -> some View {
        AuthenticationSettingsView(state: state)
    }
}

struct LocalDetailRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        LocalDetailView()
    }
}

private struct LocalDetailView: View {
    @State private var updateCount = 0

    var body: some View {
        LabScreen("Local detail", eyebrow: "Branch host ownership", symbol: "rectangle.stack.badge.plus") {
            Text("Local detail push active")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.localDetailTitle)

            LabPanel("Host ownership") {
                Text("This push is declared locally while the Settings branch also inherits push declarations from Landing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LabAction(title: "Advance local state", symbol: "arrow.triangle.2.circlepath", color: LabPalette.mint) {
                    updateCount += 1
                }
                .accessibilityIdentifier(SampleAppAccessibility.localDetailAdvanceButton)

                Text("Local updates: \(updateCount)")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(SampleAppAccessibility.localDetailUpdateCount)
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("Local Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TopLevelSheetRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        TopLevelSheetView()
    }
}

struct TopLevelCoverRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        TopLevelCoverView()
    }
}

struct TopLevelReplacementCoverRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        TopLevelReplacementCoverView()
    }
}

struct HighPriorityPassthroughSheetRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        HighPriorityPassthroughSheetView()
    }
}

struct HighPriorityBlockingSheetRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        HighPriorityBlockingSheetView()
    }
}

struct PendingPriorityRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        PendingPriorityView()
    }
}

struct NavigationBarFadeOcclusionRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        NavigationBarFadeOcclusionView()
    }
}

struct LifecycleTeardownRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        LifecycleTeardownView()
    }
}

struct PendingPriorityView: View {
    @Environment(\.unwindRoute) var unwindRoute

    var body: some View {
        ZStack {
            LabBackground()
            LabModalCard("Priority won", subtitle: "The pending elevated request blocked the normal sheet before its window started.", symbol: "flag.checkered", color: LabPalette.coral) {
                Text("Pending high-priority route")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(SampleAppAccessibility.pendingPriorityText)

                Button("Dismiss") { Task { await unwindRoute() } }
                    .labPrimaryButton(color: LabPalette.coral)
            }
        }
    }
}

struct TopLevelSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.samplePresentationSource) private var samplePresentationSource
    @Environment(Router.self) private var router

    var body: some View {
        LabModalCard("Top-level sheet", subtitle: "The nearest matching declaration decides which scope owns this presentation.", symbol: "rectangle.bottomhalf.inset.filled", color: LabPalette.blue) {
            Text("Top-level sheet")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetText)

            Text("Presented from: \(samplePresentationSource)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetPresentationSource)

            HStack {
                Button("Dismiss") { dismiss() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetDismissButton)
                Button("Chain cover") { Task { await router.present(TopLevelCoverRoute()) } }
                    .labPrimaryButton(color: LabPalette.blue)
                    .accessibilityIdentifier(SampleAppAccessibility.topLevelSheetPresentCoverButton)
            }
        }
    }
}

struct TopLevelCoverView: View {
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            LabBackground()
            LabModalCard("Top-level cover", subtitle: "A normal full-screen cover can replace the sheet that requested it.", symbol: "rectangle.fill") {
                Text("Top-level cover")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(SampleAppAccessibility.topLevelCoverText)

                Button("Present replacement cover") {
                    Task { await router.present(TopLevelReplacementCoverRoute()) }
                }
                .labPrimaryButton()
                .accessibilityIdentifier(SampleAppAccessibility.topLevelCoverPresentReplacementButton)
            }
        }
    }
}

struct TopLevelReplacementCoverView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LabBackground()
            LabModalCard("Replacement cover", subtitle: "The previous cover was replaced rather than stacked.", symbol: "arrow.triangle.2.circlepath", color: LabPalette.coral) {
                Text("Top-level replacement cover")
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(SampleAppAccessibility.topLevelReplacementCoverText)

                Button("Dismiss") { dismiss() }
                    .labPrimaryButton(color: LabPalette.coral)
                    .accessibilityIdentifier(SampleAppAccessibility.topLevelReplacementCoverDismissButton)
            }
        }
    }
}

struct HighPriorityPassthroughSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.routePhase) private var routePhase

    var body: some View {
        LabModalCard("Passthrough sheet", subtitle: "Background interaction is enabled while this high-priority route stays active.", symbol: "hand.tap.fill", color: LabPalette.blue) {
            Text("High-priority passthrough sheet · SwiftUI isPresented: \(String(isPresented))")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.highPriorityPassthroughSheetText)

            Text("Route phase: \(routePhaseLabel)")
                .font(.caption)
                .accessibilityIdentifier(SampleAppAccessibility.highPriorityPassthroughSheetRoutePhase)

            Button("Dismiss") { dismiss() }
            .labPrimaryButton(color: LabPalette.blue)
            .accessibilityIdentifier(SampleAppAccessibility.highPriorityPassthroughSheetDismissButton)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(310)])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(310)))
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

}

struct HighPriorityBlockingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        LabModalCard("Blocking sheet", subtitle: "The scrim deliberately intercepts interaction with the route underneath.", symbol: "hand.raised.fill", color: LabPalette.amber) {
            Text("High-priority blocking sheet · SwiftUI isPresented: \(String(isPresented))")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.highPriorityBlockingSheetText)

            Button("Dismiss") { dismiss() }
            .labPrimaryButton(color: LabPalette.amber)
            .accessibilityIdentifier(SampleAppAccessibility.highPriorityBlockingSheetDismissButton)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(310)])
        .samplePresentationSizing()
    }

}

struct NavigationBarFadeOcclusionView: View {
    @State private var toolbarTapCount = 0

    var body: some View {
        LabScreen("Fade chrome", eyebrow: "Navigation host", symbol: "menubar.rectangle") {
            LabPanel("Detached cover diagnostics") {
                Text("Navigation bar fade probe")
                    .font(.headline)
                    .accessibilityIdentifier(SampleAppAccessibility.navigationBarFadeText)

                LabStatus(label: "Toolbar interaction", value: "Toolbar taps: \(toolbarTapCount)", color: LabPalette.blue, symbol: "hand.tap.fill")
                    .accessibilityIdentifier(SampleAppAccessibility.navigationBarFadeToolbarTapCount)
            }
            Spacer()
        }
        .navigationTitle("Fade Chrome")
        .navigationBarTitleDisplayMode(.inline)
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

struct AppearanceSettingsRoute: SampleDeepLinkRoute, Equatable {
    let value: UUID?

    func destination() -> some View {
        AppearanceSettingsView(value: value)
    }
}

struct AlertRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        AlertView()
    }
}

struct CriticalRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        CriticalView()
    }
}

struct CriticalReplacementRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        CriticalReplacementView()
    }
}

struct MessageRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        MessageView()
    }
}

struct DismissProbeRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        DismissProbeView()
    }
}

struct NestedModalRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        NestedModalView()
    }
}

struct SettingsModalRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        SettingsModalView()
    }
}

struct RerouteChainStartRoute: SampleDeepLinkRoute {
    func resolveRoute() async -> RouteResolution {
        .reroute(RerouteChainIntermediateRoute())
    }

    func destination() -> some View {
        EmptyView()
    }
}

struct RerouteChainIntermediateRoute: SampleDeepLinkRoute {
    func resolveRoute() async -> RouteResolution {
        .reroute(RerouteChainFinalRoute())
    }

    func destination() -> some View {
        EmptyView()
    }
}

struct RerouteChainFinalRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        RerouteChainFinalView()
    }
}

struct DismissProbeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router

    var body: some View {
        LabModalCard("Dismiss probe", subtitle: "Compare nested and shared branch modal ownership, then observe the unwind hook.", symbol: "square.stack.3d.up.fill") {
            Text("Dismiss probe")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.dismissProbeText)

            Button("Present nested modal") { Task { await router.present(NestedModalRoute()) } }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(SampleAppAccessibility.dismissProbePresentNestedButton)

            Button("Present settings modal") { Task { await router.present(SettingsModalRoute()) } }
            .labPrimaryButton()
            .accessibilityIdentifier(SampleAppAccessibility.dismissProbePresentSettingsModalButton)

            Button("Dismiss & trigger hook") { dismiss() }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(SampleAppAccessibility.dismissProbeDismissButton)
        }
        .routes {
            Sheet(NestedModalRoute.self, providesNavigation: false)
        }
    }
}

struct NestedModalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LabModalCard("Nested modal", subtitle: "Owned by the dismiss probe's local route scope.", symbol: "square.stack.3d.up.fill", color: LabPalette.blue) {
            Text("Nested modal")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.nestedModalText)

            Button("Dismiss") { dismiss() }
            .labPrimaryButton(color: LabPalette.blue)
            .accessibilityIdentifier(SampleAppAccessibility.nestedModalDismissButton)
        }
    }
}

struct SettingsModalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LabModalCard("Settings modal", subtitle: "Owned by another branch, so it replaces the current shared modal layer.", symbol: "gearshape.2.fill", color: LabPalette.amber) {
            Text("Settings modal")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.settingsModalText)

            Button("Dismiss") { dismiss() }
            .labPrimaryButton(color: LabPalette.amber)
            .accessibilityIdentifier(SampleAppAccessibility.settingsModalDismissButton)
        }
    }
}

struct RerouteChainFinalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LabModalCard("Reroute chain resolved", subtitle: "Every intermediate resolution ran before this declared destination appeared.", symbol: "point.3.filled.connected.trianglepath.dotted", color: LabPalette.mint) {
            Text("Reroute chain resolved")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.rerouteChainFinalText)

            Button("Dismiss") { dismiss() }
            .labPrimaryButton(color: LabPalette.mint)
            .accessibilityIdentifier(SampleAppAccessibility.rerouteChainFinalDismissButton)
        }
    }
}

struct DroppedRoute: SampleDeepLinkRoute {
    func resolveRoute() async -> RouteResolution {
        .drop
    }

    func destination() -> some View {
        Text("Dropped route should not appear.")
            .accessibilityIdentifier(SampleAppAccessibility.droppedRouteText)
    }
}

struct UndeclaredRoute: SampleDeepLinkRoute {
    func destination() -> some View {
        Text("Undeclared route should not appear.")
            .accessibilityIdentifier(SampleAppAccessibility.undeclaredRouteText)
    }
}
