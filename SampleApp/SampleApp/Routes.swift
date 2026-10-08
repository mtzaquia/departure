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

}

struct StartInfoRoute: SampleDeepLinkRoute {

}

struct LoginRoute: SampleDeepLinkRoute, Equatable {
    let nextRoute: (any Route)?



    static func == (lhs: Self, rhs: Self) -> Bool {
        true
    }
}

struct LoginReplacementRoute: SampleDeepLinkRoute {

}

struct LoginDetailRoute: SampleDeepLinkRoute {

}

struct LoginNoticeRoute: SampleDeepLinkRoute {

}

struct ProfileRoute: SampleDeepLinkRoute {
    func resolveRoute() async -> RouteResolution {
        Storage.shared.isLoggedIn ? .allow : .reroute(LoginRoute(nextRoute: ProfileRoute()))
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


}

struct LocalDetailRoute: SampleDeepLinkRoute {

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

}

struct TopLevelCoverRoute: SampleDeepLinkRoute {

}

struct TopLevelReplacementCoverRoute: SampleDeepLinkRoute {

}

struct HighPriorityPassthroughSheetRoute: SampleDeepLinkRoute {

}

struct HighPriorityBlockingSheetRoute: SampleDeepLinkRoute {

}

struct PendingPriorityRoute: SampleDeepLinkRoute {

}

struct NavigationBarFadeOcclusionRoute: SampleDeepLinkRoute {

}

struct LifecycleTeardownRoute: SampleDeepLinkRoute {

}

struct PendingPriorityView: View {
    @Environment(\.unwindRoute) var unwindRoute

    var body: some View {
        ZStack {
            LabBackground()
            LabModalCard("Priority won", subtitle: "The pending elevated request blocked the default sheet before its window started.", symbol: "flag.checkered", color: LabPalette.coral) {
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
    @Environment(\.router) private var router

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
    @Environment(\.router) private var router

    var body: some View {
        ZStack {
            LabBackground()
            LabModalCard("Top-level cover", subtitle: "A default full-screen cover can replace the sheet that requested it.", symbol: "rectangle.fill") {
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


}

struct AlertRoute: SampleDeepLinkRoute {

}

struct CriticalRoute: SampleDeepLinkRoute {

}

struct CriticalReplacementRoute: SampleDeepLinkRoute {

}

struct MessageRoute: SampleDeepLinkRoute {

}

struct DismissProbeRoute: SampleDeepLinkRoute {

}

struct NestedModalRoute: SampleDeepLinkRoute {

}

struct SettingsModalRoute: SampleDeepLinkRoute {

}

struct RerouteChainStartRoute: SampleDeepLinkRoute {
    func resolveRoute() async -> RouteResolution {
        .reroute(RerouteChainIntermediateRoute())
    }


}

struct RerouteChainIntermediateRoute: SampleDeepLinkRoute {
    func resolveRoute() async -> RouteResolution {
        .reroute(RerouteChainFinalRoute())
    }


}

struct RerouteChainFinalRoute: SampleDeepLinkRoute {

}

struct DismissProbeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.router) private var router

    var body: some View {
        LabModalCard("Dismiss probe", subtitle: "Compare nested and shared branch modal ownership, then observe the unwind hook.", symbol: "square.stack.3d.up.fill") {
            Text("Dismiss probe")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(SampleAppAccessibility.dismissProbeText)

            Button("Present nested modal") { Task { await router.present(NestedModalRoute()) } }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(SampleAppAccessibility.dismissProbePresentNestedButton)

            Button("Present settings modal") { Task { await router.branch(LandingView.TabItem.settings).present(SettingsModalRoute()) } }
            .labPrimaryButton()
            .accessibilityIdentifier(SampleAppAccessibility.dismissProbePresentSettingsModalButton)

            Button("Dismiss & trigger hook") { dismiss() }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(SampleAppAccessibility.dismissProbeDismissButton)
        }
        .routing()
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


}

struct UndeclaredRoute: SampleDeepLinkRoute {

}


enum Destinations {
    static let landingRoute = RouteDestination(LandingRoute.self) { route, context in
        LandingView()
            .modifier(SampleRoutingContext())
    }
    static let startInfoRoute = RouteDestination(StartInfoRoute.self) { route, context in
        StartInfoView()
            .modifier(SampleRoutingContext())
    }
    static let loginRoute = RouteDestination(LoginRoute.self) { route, context in
        let nextRoute = route.nextRoute
        RoutedNavigationStack {
            LoginView(nextRoute: nextRoute)
            .modifier(SampleRoutingContext())
        }
    }
    static let loginReplacementRoute = RouteDestination(LoginReplacementRoute.self) { route, context in
        RoutedNavigationStack {
            LoginReplacementView()
            .modifier(SampleRoutingContext())
        }
    }
    static let loginDetailRoute = RouteDestination(LoginDetailRoute.self) { route, context in
        LoginDetailView()
            .modifier(SampleRoutingContext())
    }
    static let loginNoticeRoute = RouteDestination(LoginNoticeRoute.self) { route, context in
        LoginNoticeView()
            .modifier(SampleRoutingContext())
    }
    static let profileRoute = RouteDestination(ProfileRoute.self) { route, context in
        RoutedNavigationStack {
            ProfileView()
            .modifier(SampleRoutingContext())
        }
    }
    static let authenticationSettingsRoute = RouteDestination(AuthenticationSettingsRoute.self) { route, context in
        let state = route.state
        AuthenticationSettingsView(state: state)
            .modifier(SampleRoutingContext())
    }
    static let localDetailRoute = RouteDestination(LocalDetailRoute.self) { route, context in
        LocalDetailView()
            .modifier(SampleRoutingContext())
    }
    static let topLevelSheetRoute = RouteDestination(TopLevelSheetRoute.self) { route, context in
        TopLevelSheetView()
            .modifier(SampleRoutingContext())
    }
    static let topLevelCoverRoute = RouteDestination(TopLevelCoverRoute.self) { route, context in
        TopLevelCoverView()
            .modifier(SampleRoutingContext())
    }
    static let topLevelReplacementCoverRoute = RouteDestination(TopLevelReplacementCoverRoute.self) { route, context in
        TopLevelReplacementCoverView()
            .modifier(SampleRoutingContext())
    }
    static let highPriorityPassthroughSheetRoute = RouteDestination(HighPriorityPassthroughSheetRoute.self) { route, context in
        HighPriorityPassthroughSheetView()
            .modifier(SampleRoutingContext())
    }
    static let highPriorityBlockingSheetRoute = RouteDestination(HighPriorityBlockingSheetRoute.self) { route, context in
        HighPriorityBlockingSheetView()
            .modifier(SampleRoutingContext())
    }
    static let pendingPriorityRoute = RouteDestination(PendingPriorityRoute.self) { route, context in
        PendingPriorityView()
            .modifier(SampleRoutingContext())
    }
    static let navigationBarFadeOcclusionRoute = RouteDestination(NavigationBarFadeOcclusionRoute.self) { route, context in
        RoutedNavigationStack {
            NavigationBarFadeOcclusionView()
            .modifier(SampleRoutingContext())
        }
    }
    static let lifecycleTeardownRoute = RouteDestination(LifecycleTeardownRoute.self) { route, context in
        LifecycleTeardownView()
            .modifier(SampleRoutingContext())
    }
    static let appearanceSettingsRoute = RouteDestination(AppearanceSettingsRoute.self) { route, context in
        let value = route.value
        AppearanceSettingsView(value: value)
            .modifier(SampleRoutingContext())
    }
    static let alertRoute = RouteDestination(AlertRoute.self) { route, context in
        AlertView()
            .modifier(SampleRoutingContext())
    }
    static let criticalRoute = RouteDestination(CriticalRoute.self) { route, context in
        CriticalView()
            .modifier(SampleRoutingContext())
    }
    static let criticalReplacementRoute = RouteDestination(CriticalReplacementRoute.self) { route, context in
        CriticalReplacementView()
            .modifier(SampleRoutingContext())
    }
    static let messageRoute = RouteDestination(MessageRoute.self) { route, context in
        MessageView()
            .modifier(SampleRoutingContext())
    }
    static let dismissProbeRoute = RouteDestination(DismissProbeRoute.self) { route, context in
        DismissProbeView()
            .modifier(SampleRoutingContext())
    }
    static let nestedModalRoute = RouteDestination(NestedModalRoute.self) { route, context in
        NestedModalView()
            .modifier(SampleRoutingContext())
    }
    static let settingsModalRoute = RouteDestination(SettingsModalRoute.self) { route, context in
        SettingsModalView()
            .modifier(SampleRoutingContext())
    }
    static let rerouteChainStartRoute = RouteDestination(RerouteChainStartRoute.self) { route, context in
        EmptyView()
            .modifier(SampleRoutingContext())
    }
    static let rerouteChainIntermediateRoute = RouteDestination(RerouteChainIntermediateRoute.self) { route, context in
        EmptyView()
            .modifier(SampleRoutingContext())
    }
    static let rerouteChainFinalRoute = RouteDestination(RerouteChainFinalRoute.self) { route, context in
        RerouteChainFinalView()
            .modifier(SampleRoutingContext())
    }
    static let droppedRoute = RouteDestination(DroppedRoute.self) { route, context in
        Text("Dropped route should not appear.")
            .accessibilityIdentifier(SampleAppAccessibility.droppedRouteText)
            .modifier(SampleRoutingContext())
    }
    static let undeclaredRoute = RouteDestination(UndeclaredRoute.self) { route, context in
        Text("Undeclared route should not appear.")
            .accessibilityIdentifier(SampleAppAccessibility.undeclaredRouteText)
            .modifier(SampleRoutingContext())
    }
}


enum AppRouteMaps {
    static let authentication = RouteMap {
        Sheet(Destinations.topLevelSheetRoute)
    }
    static let landing = RouteMap {
        Sheet(Destinations.topLevelSheetRoute)
        Cover(Destinations.topLevelCoverRoute)
        Cover(Destinations.topLevelReplacementCoverRoute)
        Branches {
            Branch(LandingView.TabItem.home) {
                Push(Destinations.lifecycleTeardownRoute) { LifecycleTeardownMap.routes }
                Sheet(Destinations.profileRoute)
                Sheet(Destinations.dismissProbeRoute) { Sheet(Destinations.nestedModalRoute) }
                Cover(Destinations.messageRoute, transition: .fade)
                Cover(Destinations.navigationBarFadeOcclusionRoute, transition: .fade)
            }
            Branch(LandingView.TabItem.settings) {
                Push(Destinations.localDetailRoute)
                Push(Destinations.appearanceSettingsRoute) {
                    Push(Destinations.authenticationSettingsRoute) { authentication }
                }
                Push(Destinations.authenticationSettingsRoute) { authentication }
                Sheet(Destinations.settingsModalRoute)
                Sheet(Destinations.rerouteChainFinalRoute)
            }
        }
    }
    static let root = RootRouteMap(id: SampleAppAccessibility.startScopeID) {
        Cover(Destinations.landingRoute) { landing }
        Cover(SplitBranchMap.destination) { SplitBranchMap.routes }
        Sheet(Destinations.startInfoRoute)
    } highPriority: {
        Cover(Destinations.loginRoute) {
            Push(Destinations.loginDetailRoute)
            Sheet(Destinations.loginNoticeRoute)
        }
        Cover(Destinations.loginReplacementRoute)
        Cover(Destinations.alertRoute, transition: .fade)
        Sheet(Destinations.highPriorityPassthroughSheetRoute)
        Sheet(Destinations.highPriorityBlockingSheetRoute)
        Cover(Destinations.pendingPriorityRoute)
    } criticalPriority: {
        Cover(Destinations.criticalRoute, transition: .fade)
        Cover(Destinations.criticalReplacementRoute, transition: .fade)
    }
}
