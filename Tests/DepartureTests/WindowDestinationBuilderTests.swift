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
import Testing
@testable import Departure

private struct WindowDestinationTestValueKey: EnvironmentKey {
    static let defaultValue = "default"
}

private extension EnvironmentValues {
    var windowDestinationTestValue: String {
        get { self[WindowDestinationTestValueKey.self] }
        set { self[WindowDestinationTestValueKey.self] = newValue }
    }
}

@MainActor
private final class WindowDestinationRecorder {
    var values: [String] = []
}

private struct RecordingWindowDestinationView: View {
    let destination: RouteView

    init(
        destination: RouteView,
        environment: EnvironmentValues,
        recorder: WindowDestinationRecorder
    ) {
        self.destination = destination
        recorder.values.append(environment.windowDestinationTestValue)
    }

    var body: some View {
        destination
    }
}

@MainActor
@Suite
struct WindowDestinationBuilderTests {
    @Test func withRouterDefaultWindowDestinationBuildsRouteDestination() {
        let host = WithRouter(routes: RootRouteMap {}) {
            Text("Root")
        }

        #expect(host.windowDestinationBuilder.hasWindowDestination == false)

        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "source"

        let route = PresentedRoute(scope: RouteScope(id: RootRoute().id, route: RootRoute()))
        let snapshot = RouteDestinationSnapshot(
            route: PresentedRoute(scope: route.scope, sourceEnvironment: environment),
            destinationBuilder: host.windowDestinationBuilder
        )

        #expect(snapshot.route == route)
    }

    @Test func withRouterRegistersCustomWindowDestinationBuilderOnRouter() {
        let router = RouterEngine()
        let recorder = WindowDestinationRecorder()
        let host = WithRouter(routes: RootRouteMap {}, router: RootRouter(engine: router)) {
            Text("Root")
        } windowDestination: { destination, environment in
            RecordingWindowDestinationView(
                destination: destination,
                environment: environment,
                recorder: recorder
            )
        }
        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "redirected"
        let route = PresentedRoute(scope: RouteScope(id: RootRoute().id, route: RootRoute()), sourceEnvironment: environment)

        _ = RouteDestinationSnapshot(
            route: route,
            destinationBuilder: router.windowDestinationBuilder
        )

        #expect(router.windowDestinationBuilder.hasWindowDestination)
        #expect(recorder.values == ["redirected"])
        _ = host
    }

    @Test func windowDestinationReceivesCapturedSourceEnvironment() async throws {
        let router = RouterEngine()
        let recorder = WindowDestinationRecorder()

        router.root.defineTestMap(id: nil, selection: nil, definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .cover(priority: .high, transition: .slide))._routeDeclarations),
            ])

        await router.requestRoute(LoginRoute())
        let presentation = try #require(router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue)
        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "forwarded"

        let destinationBuilder = WindowDestinationBuilder { destination, environment in
            RecordingWindowDestinationView(
                destination: destination,
                environment: environment,
                recorder: recorder
            )
            .environment(
                \.windowDestinationTestValue,
                environment.windowDestinationTestValue
            )
        }

        _ = RouteDestinationSnapshot(
            route: PresentedRoute(scope: presentation.scope, sourceEnvironment: environment),
            destinationBuilder: destinationBuilder
        )

        #expect(recorder.values == ["forwarded"])
    }

    @Test func routeDeclarationInstallationAttachesSourceEnvironmentForHighPriorityPresentation() async throws {
        let router = RouterEngine()
        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "installed"

        router.root.defineTestMap(id: nil, selection: nil, definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .cover(priority: .high, transition: .slide))._routeDeclarations),
            ], environment: environment)

        await router.requestRoute(LoginRoute())
        let presentation = try #require(router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue)

        #expect(presentation.sourceEnvironment.windowDestinationTestValue == "installed")
    }

    @Test func elevatedPresentationRetainsSourceEnvironmentAfterOriginScopeIsReleased() throws {
        let router = RouterEngine()
        let declaration = AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .cover(priority: .high, transition: .slide))._routeDeclarations[0]
        let presentedScope = RouteScope(id: LoginRoute().id, route: LoginRoute())
        weak var releasedOrigin: RouteScope?

        do {
            let origin = RouteScope(id: RootRoute().id, route: RootRoute())
            var environment = EnvironmentValues()
            environment.windowDestinationTestValue = "retained"
            origin.updateSourceEnvironment(environment)
            releasedOrigin = origin

            presentedScope.attachPresentation(to: origin, declaration: declaration)
            router.spaces.highSpace = RouteSpace(
                priority: .high,
                root: presentedScope
            )
        }

        #expect(releasedOrigin == nil)
        let presentation = try #require(router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue)
        #expect(presentation.sourceEnvironment.windowDestinationTestValue == "retained")
    }

    @Test func existingWindowDestinationSnapshotKeepsCapturedSourceEnvironment() async throws {
        let router = RouterEngine()
        let recorder = WindowDestinationRecorder()
        let destinationBuilder = WindowDestinationBuilder { destination, environment in
            RecordingWindowDestinationView(
                destination: destination,
                environment: environment,
                recorder: recorder
            )
        }
        var initialEnvironment = EnvironmentValues()
        initialEnvironment.windowDestinationTestValue = "initial"

        router.root.defineTestMap(id: nil, selection: nil, definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .cover(priority: .high, transition: .slide))._routeDeclarations),
            ], environment: initialEnvironment)

        await router.requestRoute(LoginRoute())
        let initialPresentation = try #require(router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue)

        _ = RouteDestinationSnapshot(
            route: initialPresentation,
            destinationBuilder: destinationBuilder
        )

        var updatedEnvironment = EnvironmentValues()
        updatedEnvironment.windowDestinationTestValue = "updated"
        router.root.defineTestMap(id: nil, selection: nil, definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .cover(priority: .high, transition: .slide))._routeDeclarations),
            ], environment: updatedEnvironment)

        let updatedPresentation = try #require(router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue)

        #expect(updatedPresentation == initialPresentation)
        #expect(updatedPresentation.sourceEnvironment.windowDestinationTestValue == "updated")
        #expect(recorder.values == ["initial"])
    }

    @Test func replacingHighPriorityPresentationUsesReplacementSourceEnvironment() async throws {
        let router = RouterEngine()
        let recorder = WindowDestinationRecorder()
        let destinationBuilder = WindowDestinationBuilder { destination, environment in
            RecordingWindowDestinationView(
                destination: destination,
                environment: environment,
                recorder: recorder
            )
        }
        let routeDeclarations = [
            RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .cover(priority: .high, transition: .slide))._routeDeclarations
                    + AnyRouteDeclaration(RouteDestination(AlertRoute.self) { route, _ in EmptyView() }, kind: .cover(priority: .high, transition: .slide))._routeDeclarations),
        ]
        var initialEnvironment = EnvironmentValues()
        initialEnvironment.windowDestinationTestValue = "initial"

        router.root.defineTestMap(id: nil, selection: nil, definitions: routeDeclarations, environment: initialEnvironment)

        await router.requestRoute(LoginRoute())
        let initialPresentation = try #require(router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue)

        _ = RouteDestinationSnapshot(
            route: initialPresentation,
            destinationBuilder: destinationBuilder
        )

        var replacementEnvironment = EnvironmentValues()
        replacementEnvironment.windowDestinationTestValue = "replacement"
        router.root.defineTestMap(id: nil, selection: nil, definitions: routeDeclarations, environment: replacementEnvironment)

        await router.requestRoute(AlertRoute())
        let replacementPresentation = try #require(router.elevatedRoutePresentationBinding(
            priority: .high,
            matching: .cover(.slide)
        ).wrappedValue)

        _ = RouteDestinationSnapshot(
            route: replacementPresentation,
            destinationBuilder: destinationBuilder
        )

        #expect(replacementPresentation != initialPresentation)
        #expect(replacementPresentation.scope.route is AlertRoute)
        #expect(recorder.values == ["initial", "replacement"])
    }

    @Test func defaultPresentationUsesDeclaringScopeSourceEnvironment() async throws {
        let router = RouterEngine()
        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "declaring"

        router.root.defineTestMap(id: nil, selection: nil, definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(LoginRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: .default))._routeDeclarations),
            ], environment: environment)

        await router.requestRoute(LoginRoute())
        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.sourceEnvironment.windowDestinationTestValue == "declaring")
    }

    @Test func branchContainerPresentationUsesContainerSourceEnvironment() async throws {
        let router = RouterEngine()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        var containerEnvironment = EnvironmentValues()
        containerEnvironment.windowDestinationTestValue = "container"
        var branchEnvironment = EnvironmentValues()
        branchEnvironment.windowDestinationTestValue = "branch"

        router.defaultSpace.rootPath.replaceTestPath([landingScope])
        landingScope.defineTestMap(id: RootRoute().id, selection: AnyRouteBranchSelection(selection), definitions: RouteDeclarationBuilder.buildBlock(
                RouteDeclarationBuilder.buildExpression(
                    AnyRouteDeclaration(RouteDestination(MessageRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: .default))
                ),
                RouteDeclarationBuilder.buildExpression(
                    Branches { Branch(AppTab.home) {
                        AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, kind: .push)
                    } }
                )
            ), environment: containerEnvironment)

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.defineTestMap(id: AnyHashable(AppTab.home), selection: nil, definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, kind: .push)._routeDeclarations),
            ], environment: branchEnvironment)
        landingScope.attachTestBranch(homeScope, for: AppTab.home, environment: branchEnvironment)

        await router.requestRoute(SettingsRoute())
        await router.requestRoute(MessageRoute())

        let presentation = try #require(router.routePresentationBinding(
            from: landingScope,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.sourceEnvironment.windowDestinationTestValue == "container")
    }

    @Test func defaultSheetPresentationDoesNotUseWindowDestinationBuilder() async throws {
        let router = RouterEngine()
        let recorder = WindowDestinationRecorder()

        let host = WithRouter(routes: RootRouteMap {}) {
            Text("Root")
        } windowDestination: { destination, environment in
            RecordingWindowDestinationView(
                destination: destination,
                environment: environment,
                recorder: recorder
            )
        }

        #expect(host.windowDestinationBuilder.hasWindowDestination)

        router.root.defineTestMap(id: nil, selection: nil, definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, kind: .sheet(priority: .default))._routeDeclarations),
            ])

        await router.requestRoute(SettingsRoute())
        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.scope === router.defaultSpace.rootPath.last)
        #expect(recorder.values.isEmpty)
        _ = host
    }

    #if !canImport(UIKit)
    @Test func elevatedBridgeUsesWindowDestinationBuilderOnMacOS() {
        let recorder = WindowDestinationRecorder()
        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "macOS elevated"
        let presentation = PresentedRoute(scope: RouteScope(id: SettingsRoute().id, route: SettingsRoute()), sourceEnvironment: environment)
        let builder = WindowDestinationBuilder { destination, environment in
            RecordingWindowDestinationView(
                destination: destination, environment: environment, recorder: recorder
            )
        }
        let bridge = ElevatedPriorityPresentationWindowBridge(
            priority: .high,
            route: .constant(presentation),
            sourceScenePhase: .active,
            windowDestinationBuilder: builder
        ) { snapshot, _ in
            snapshot.destination
        }

        _ = bridge.body
        #expect(recorder.values == ["macOS elevated"])
    }
    #endif

    @Test func defaultFadeCoverDestinationUsesWindowDestinationBuilder() async throws {
        let router = RouterEngine()
        let recorder = WindowDestinationRecorder()

        router.root.defineTestMap(id: nil, selection: nil, definitions: [
                RouteScopeDeclaration(routes: AnyRouteDeclaration(RouteDestination(SettingsRoute.self) { route, _ in EmptyView() }, kind: .cover(priority: .default, transition: .fade))._routeDeclarations),
            ])

        await router.requestRoute(SettingsRoute())
        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .cover(.fade)
        ).wrappedValue)
        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "fade"

        let destinationBuilder = WindowDestinationBuilder { destination, environment in
            RecordingWindowDestinationView(
                destination: destination,
                environment: environment,
                recorder: recorder
            )
        }

        _ = RouteDestinationSnapshot(
            route: PresentedRoute(scope: presentation.scope, sourceEnvironment: environment),
            destinationBuilder: destinationBuilder
        )

        #expect(recorder.values == ["fade"])
    }
}
