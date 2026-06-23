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
        let host = WithRouter {
            Text("Root")
        }

        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "source"

        let route = RoutePresentation(
            scope: RouteScope(id: RootRoute().id, route: RootRoute()),
            declaration: Push(RootRoute.self)._routeDeclarations[0]
        )
        let snapshot = RouteDestinationSnapshot(
            route: RoutePresentation(
                scope: route.scope,
                declaration: route.declaration,
                sourceEnvironment: environment
            ),
            destinationBuilder: host.windowDestinationBuilder
        )

        #expect(snapshot.route == route)
    }

    @Test func windowDestinationReceivesCapturedSourceEnvironment() async throws {
        let router = Router()
        let recorder = WindowDestinationRecorder()

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ]
        )

        await router.requestRoute(LoginRoute())
        let presentation = try #require(router.highPriorityRoutePresentationBinding(
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
            route: RoutePresentation(
                scope: presentation.scope,
                declaration: presentation.declaration,
                sourceEnvironment: environment
            ),
            destinationBuilder: destinationBuilder
        )

        #expect(recorder.values == ["forwarded"])
    }

    @Test func routeDeclarationInstallationAttachesSourceEnvironmentForHighPriorityPresentation() async throws {
        let router = Router()
        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "installed"

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ],
            sourceEnvironment: environment
        )

        await router.requestRoute(LoginRoute())
        let presentation = try #require(router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue)

        #expect(presentation.sourceEnvironment.windowDestinationTestValue == "installed")
    }

    @Test func existingWindowDestinationSnapshotKeepsCapturedSourceEnvironment() async throws {
        let router = Router()
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

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ],
            sourceEnvironment: initialEnvironment
        )

        await router.requestRoute(LoginRoute())
        let initialPresentation = try #require(router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue)

        _ = RouteDestinationSnapshot(
            route: initialPresentation,
            destinationBuilder: destinationBuilder
        )

        var updatedEnvironment = EnvironmentValues()
        updatedEnvironment.windowDestinationTestValue = "updated"
        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations),
            ],
            sourceEnvironment: updatedEnvironment
        )

        let updatedPresentation = try #require(router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue)

        #expect(updatedPresentation == initialPresentation)
        #expect(updatedPresentation.sourceEnvironment.windowDestinationTestValue == "updated")
        #expect(recorder.values == ["initial"])
    }

    @Test func replacingHighPriorityPresentationUsesReplacementSourceEnvironment() async throws {
        let router = Router()
        let recorder = WindowDestinationRecorder()
        let destinationBuilder = WindowDestinationBuilder { destination, environment in
            RecordingWindowDestinationView(
                destination: destination,
                environment: environment,
                recorder: recorder
            )
        }
        let routeDeclarations = [
            RouteScopeDeclaration(
                routes: Cover(LoginRoute.self, priority: .high)._routeDeclarations
                    + Cover(AlertRoute.self, priority: .high)._routeDeclarations
            ),
        ]
        var initialEnvironment = EnvironmentValues()
        initialEnvironment.windowDestinationTestValue = "initial"

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: routeDeclarations,
            sourceEnvironment: initialEnvironment
        )

        await router.requestRoute(LoginRoute())
        let initialPresentation = try #require(router.highPriorityRoutePresentationBinding(
            matching: .cover(.slide)
        ).wrappedValue)

        _ = RouteDestinationSnapshot(
            route: initialPresentation,
            destinationBuilder: destinationBuilder
        )

        var replacementEnvironment = EnvironmentValues()
        replacementEnvironment.windowDestinationTestValue = "replacement"
        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: routeDeclarations,
            sourceEnvironment: replacementEnvironment
        )

        await router.requestRoute(AlertRoute())
        let replacementPresentation = try #require(router.highPriorityRoutePresentationBinding(
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

    @Test func normalPresentationUsesDeclaringScopeSourceEnvironment() async throws {
        let router = Router()
        var environment = EnvironmentValues()
        environment.windowDestinationTestValue = "declaring"

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(LoginRoute.self)._routeDeclarations),
            ],
            sourceEnvironment: environment
        )

        await router.requestRoute(LoginRoute())
        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.sourceEnvironment.windowDestinationTestValue == "declaring")
    }

    @Test func branchContainerPresentationUsesContainerSourceEnvironment() async throws {
        let router = Router()
        let (selection, _) = tabSelection(.home)
        let landingScope = RouteScope(id: RootRoute().id, route: RootRoute())
        var containerEnvironment = EnvironmentValues()
        containerEnvironment.windowDestinationTestValue = "container"
        var branchEnvironment = EnvironmentValues()
        branchEnvironment.windowDestinationTestValue = "branch"

        router.rootPath.scopes = [landingScope]
        landingScope.installRouteDeclarations(
            id: RootRoute().id,
            branchSelection: AnyRouteBranchSelection(selection),
            routeDeclarations: BranchedRouteDeclarationBuilder<AppTab>.buildBlock(
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Sheet(MessageRoute.self)
                ),
                BranchedRouteDeclarationBuilder<AppTab>.buildExpression(
                    Branch(.home) {
                        Push(SettingsRoute.self)
                    }
                )
            ),
            sourceEnvironment: containerEnvironment
        )

        let homeScope = RouteScope(id: AnyHashable(AppTab.home), route: nil)
        homeScope.installRouteDeclarations(
            id: AnyHashable(AppTab.home),
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Push(SettingsRoute.self)._routeDeclarations),
            ],
            sourceEnvironment: branchEnvironment
        )
        landingScope.registerBranchScope(homeScope, for: AppTab.home, sourceEnvironment: branchEnvironment)

        await router.requestRoute(SettingsRoute())
        await router.requestRoute(MessageRoute())

        let presentation = try #require(router.routePresentationBinding(
            from: landingScope,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.sourceEnvironment.windowDestinationTestValue == "container")
    }

    @Test func normalPresentationResolutionDoesNotUseWindowDestinationBuilder() async throws {
        let router = Router()
        let recorder = WindowDestinationRecorder()

        let host = WithRouter {
            Text("Root")
        } windowDestination: { destination, environment in
            RecordingWindowDestinationView(
                destination: destination,
                environment: environment,
                recorder: recorder
            )
        }

        router.root.installRouteDeclarations(
            id: nil,
            branchSelection: nil,
            routeDeclarations: [
                RouteScopeDeclaration(routes: Sheet(SettingsRoute.self)._routeDeclarations),
            ]
        )

        await router.requestRoute(SettingsRoute())
        let presentation = try #require(router.routePresentationBinding(
            from: router.root,
            matching: .sheet
        ).wrappedValue)

        #expect(presentation.scope === router.rootPath.last)
        #expect(recorder.values.isEmpty)
        _ = host
    }
}
