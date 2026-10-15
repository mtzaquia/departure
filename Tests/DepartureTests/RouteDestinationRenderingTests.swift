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
import RouteDomainFixtures
@testable import Departure
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

private let nativeDestinationTestsEnabled = ProcessInfo.processInfo.environment["DEPARTURE_RUN_HOSTED_UI_TESTS"] == "1"

@MainActor
// Native windows run separately from the unhosted package suite. UIKit needs a scene-backed host.
@Suite(.serialized, .enabled(if: nativeDestinationTestsEnabled))
struct RouteDestinationRenderingTests {
    @Test func branchSelectionReconcilesInitialValueAndOwnerChanges() async throws {
        let router = RootRouter()
        let control = SelectionReconciliationControl()
        let host = WithRouter(routes: RootRouteMap {
            Branches { Branch("first") {}; Branch("second") {} }
        }, router: router) {
            SelectionReconciliationSources(control: control)
        }
        let window = mount(host)
        defer { close(window) }
        let scope = router.engine.root
        try #require(await waitUntil { scope.branchSelection != nil && scope.activeBranch == AnyHashable("second") })

        control.showsDuplicate = true
        try #require(await waitUntil { scope.hasConflictingBranchSelection && control.duplicate == "second" })
        // Resolve ownership in the same update as a conflicting native selection write.
        // The remaining owner must first restore the model, then accept later user changes.
        control.duplicate = "first"
        control.showsPrimary = false
        try #require(await waitUntil { scope.branchSelection != nil && control.duplicate == "second" })
        #expect(scope.activeBranch == AnyHashable("second"))
        control.duplicate = "first"
        try #require(await waitUntil { scope.activeBranch == AnyHashable("first") })

        control.showsDuplicate = false
        try #require(await waitUntil { scope.branchSelection == nil })
        control.showsPrimary = true
        try #require(await waitUntil { scope.branchSelection != nil && scope.activeBranch == AnyHashable("second") })
    }

    #if canImport(AppKit)
    @Test func unadmittedRouteTeardownCompletesWhileItsCustomWrapperIsRetained() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Replace(DomainOnlyRoute.self)
        } destinations: {
            RouteDestination(DomainOnlyRoute.self) { _, _ in Text("Pending route") }
        })
        engine.routeScopeDidInstallInView(engine.root)
        await engine.present(DomainOnlyRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        let lifetime = NativePresentationLifetime()
        let control = CustomizedDestinationControl()
        let builder = WindowDestinationBuilder { view, _ in
            ConditionalCustomizedDestination(control: control, destination: view)
        }
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0, destinationBuilder: builder, nativePresentation: lifetime) }
        let snapshot = try #require(lifetime.presentation)
        let host = NSHostingView(rootView: snapshot.destination.environment(\.routerEngine, engine))
        host.frame = NSRect(x: 0, y: 0, width: 390, height: 500)
        host.layoutSubtreeIfNeeded()
        try #require(await waitUntil { lifecycleBridgeCount(in: host) == 2 })
        #expect(!lifetime.isAdmitted)
        lifetime.synchronize(nil) { .init(route: $0) }
        #expect(scope.isAwaitingPresentationEnd)
        control.showsRoute = false
        host.layoutSubtreeIfNeeded()
        try #require(await waitUntil { lifetime.presentation == nil })
        #expect(lifecycleBridgeCount(in: host) == 1)
        #expect(!scope.isAwaitingPresentationEnd)
        withExtendedLifetime(host) {}
    }
    #endif

    @Test func customizedContentAdmitsItsModalEvenWhenItTemporarilyOmitsRouteView() async throws {
        let engine = RouterEngine()
        let route = PresentedRoute(scope: RouteScope(id: "custom wrapper", route: nil))
        let lifetime = NativePresentationLifetime()
        let builder = WindowDestinationBuilder { _, _ in Text("Preparing customized content") }
        lifetime.synchronize(route) { .init(route: $0, destinationBuilder: builder, nativePresentation: lifetime) }
        let snapshot = try #require(lifetime.presentation)
        let window = mount(snapshot.destination.environment(\.routerEngine, engine))
        defer { close(window) }
        try #require(await waitUntil { lifetime.isAdmitted })
        #expect(!route.scope.isInstalledInView)
        lifetime.synchronize(nil) { .init(route: $0) }
        lifetime.didDismantleDestination(of: snapshot.id)
        #expect(route.scope.isAwaitingPresentationEnd)
        lifetime.completeDismissal(of: snapshot.id, in: engine)
        #expect(!route.scope.isAwaitingPresentationEnd)
    }

    @Test func destinationUsesOneBridgeForHostRegistrationAndNativeAdmission() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Replace(DomainOnlyRoute.self)
        } destinations: {
            RouteDestination(DomainOnlyRoute.self) { _, _ in Text("Single lifecycle source") }
        })
        engine.routeScopeDidInstallInView(engine.root)
        await engine.present(DomainOnlyRoute())
        let scope = try #require(engine.defaultSpace.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope)) { .init(route: $0, nativePresentation: lifetime) }
        let snapshot = try #require(lifetime.presentation)
        let window = mount(snapshot.destination.environment(\.routerEngine, engine))
        defer { close(window) }
        try #require(await waitUntil { scope.isAvailableForPresentation && scope.presentationHostID != nil })
        #expect(lifecycleBridgeCount(in: try #require(window.contentViewForLifecycleTest)) == 1)
        lifetime.synchronize(nil) { .init(route: $0) }
        lifetime.didDismantleDestination(of: snapshot.id)
        // Window admission must have reached the native owner through that same bridge.
        #expect(scope.isAwaitingPresentationEnd)
        lifetime.completeDismissal(of: snapshot.id, in: engine)
        #expect(!scope.isAwaitingPresentationEnd)
    }

    private func lifecycleBridgeCount(in view: PlatformView) -> Int {
        (view is ViewLifecycleBridge.LifecycleView ? 1 : 0)
            + view.subviews.reduce(0) { $0 + lifecycleBridgeCount(in: $1) }
    }

    @Test func replacementContextTracksEnvironmentAndKeepsCapturedActionsScoped() async throws {
        let router = RootRouter()
        let engine = router.engine
        let control = DestinationEnvironmentControl()
        let recorder = RenderedDestinationRecorder()
        let destination = RouteDestination(DomainOnlyRoute.self) { _, context in
            recorder.context = context
            recorder.values.append(context.environment.destinationTestValue)
            return DestinationEnvironmentReader(recorder: recorder)
        }
        let host = WithRouter(routes: RootRouteMap { testReplace(destination) }, router: router) {
            DestinationEnvironmentHost(control: control)
        }
        let window = mount(host)
        defer { close(window) }
        try #require(await waitUntil { engine.root.isInstalledInView && engine.root.presentationHostID != nil })
        await router.current.present(DomainOnlyRoute())
        try #require(await waitUntil { recorder.environment != nil && recorder.context != nil })
        let firstScope = try #require(engine.defaultSpace.rootPath.last)
        let context = try #require(recorder.context)
        let initialValue = context.environment.destinationTestValue
        #expect(context.presentation.style == .replace)
        #expect(context.presentation.priority == .default)
        #expect(context.router == Router(engine: engine, scope: firstScope))
        #expect(context.environment.router == context.router)
        #expect(recorder.unwindRoute == context.unwindRoute)
        #expect(context.environment.routeScope === firstScope)
        #expect(context.environment.routePhase == .active)
        #expect(recorder.environment?.router == context.router)
        #expect(recorder.environment?.destinationTestValue == "initial")

        control.value = "updated"
        try #require(await waitUntil { recorder.context?.environment.destinationTestValue == "updated" })
        #expect(recorder.values.contains("updated"))
        #expect(initialValue == "initial")
        #expect(await context.unwindRoute())
        try #require(await waitUntil { engine.defaultSpace.rootPath.isEmpty })
        await router.current.present(DomainOnlyRoute())
        let nextScope = try #require(engine.defaultSpace.rootPath.last)
        #expect(nextScope !== firstScope)
        #expect(!(await context.unwindRoute()))
        await context.router.present(DomainOnlyRoute())
        #expect(engine.defaultSpace.rootPath.last === nextScope)
        #expect(await router.current.unwind(to: .root))
    }

    @Test(arguments: [RoutePresentation.Style.push, .sheet, .cover(.slide), .cover(.fade)])
    func contextReportsMatchedPresentationStyle(style: RoutePresentation.Style) async throws {
        let router = RootRouter()
        let engine = router.engine
        let recorder = RenderedDestinationRecorder()
        let destination = RouteDestination(DomainOnlyRoute.self) { _, context in
            recorder.context = context
            return DestinationEnvironmentReader(recorder: recorder)
        }
        let routes = RootRouteMap {
            if style == .push { testPush(destination) }
            if style == .sheet { testSheet(destination) }
            if case .cover(let transition) = style { testCover(destination, transition: transition) }
        }
        let host = WithRouter(routes: routes, router: router) {
            NavigationStack {
                Text("Root").routing()
            }
            .environment(\.destinationTestValue, "local")
        } windowDestination: { destination, environment in
            destination.environment(\.destinationTestValue, environment.destinationTestValue)
        }
        let window = mount(host)
        defer { close(window) }
        try #require(await waitUntil { engine.root.isInstalledInView && engine.root.presentationHostID != nil })
        await router.current.present(DomainOnlyRoute())
        try #require(await waitUntil { recorder.context != nil && recorder.environment != nil })
        let context = try #require(recorder.context)
        #expect(context.presentation.style == style)
        #expect(context.presentation.priority == .default)
        #expect(context.environment.destinationTestValue == "local")
        #expect(recorder.environment?.destinationTestValue == "local")
        #expect(context.environment.router == context.router)
        #expect(recorder.unwindRoute == context.unwindRoute)
        #expect(recorder.environment?.router == context.router)
        if style == .push {
            #expect(await context.unwindRoute())
        } else {
            recorder.context = nil
            recorder.environment = nil
            recorder.dismiss?()
            try #require(await waitUntil { engine.defaultSpace.rootPath.isEmpty })
        }
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func elevatedChildrenReceiveLocalStyleAndEffectivePriority(priority: RoutePriority) async throws {
        let router = RootRouter()
        let engine = router.engine
        let parentRecorder = RenderedDestinationRecorder()
        let childRecorder = RenderedDestinationRecorder()
        let child = RouteDestination(NumberedRoute.self) { route, context in
            childRecorder.context = context
            childRecorder.number = route.number
            return DestinationEnvironmentReader(recorder: childRecorder)
        }
        let parent = RouteDestination(DomainOnlyRoute.self) { _, context in
            parentRecorder.context = context
            return NavigationStack { DestinationEnvironmentReader(recorder: parentRecorder).routing() }
        }
        let routes = RootRouteMap {
            HighPriority {
                if priority == .high { testCover(parent, transition: .fade) { testPush(child) } }
            }
            CriticalPriority {
                if priority == .critical { testCover(parent, transition: .fade) { testPush(child) } }
            }
        }
        let host = WithRouter(routes: routes, router: router) {
            Text("Root")
                .routing()
                .environment(\.destinationTestValue, "forwarded")
        } windowDestination: { destination, environment in
            destination.environment(\.destinationTestValue, environment.destinationTestValue)
        }
        let window = mount(host)
        defer { close(window) }
        try #require(await waitUntil { engine.root.isInstalledInView && engine.root.presentationHostID != nil })
        await router.current.present(DomainOnlyRoute())
        try #require(await waitUntil { parentRecorder.context != nil })
        let parentContext = try #require(parentRecorder.context)
        #expect(parentContext.presentation == .init(style: .cover(.fade), priority: priority))
        let parentScope = try #require(engine.spaces.space(for: priority)?.root)
        try #require(await waitUntil { parentScope.isInstalledInView && parentScope.presentationHostID != nil })
        await parentContext.router.present(NumberedRoute(number: 17))
        try #require(await waitUntil { childRecorder.context != nil && childRecorder.environment != nil })
        let childContext = try #require(childRecorder.context)
        #expect(childRecorder.number == 17)
        #expect(childContext.presentation == .init(style: .push, priority: priority))
        #expect(childContext.environment.destinationTestValue == "forwarded")
        #expect(childRecorder.environment?.router == childContext.router)
        #expect(await childContext.unwindRoute())
        recorderDismiss(parentRecorder)
        try #require(await waitUntil { engine.spaces.space(for: priority) == nil })
    }

    @Test(arguments: [RoutePresentation.Style.sheet, .cover(.fade)], [false, true])
    func ancestorReaderDismissesItsFlow(style: RoutePresentation.Style, childUnwindsFirst: Bool) async throws {
        let router = RootRouter()
        let recorder = RenderedDestinationRecorder()
        let parent = RouteDestination(DomainOnlyRoute.self) { _, _ in
            NavigationStack { Text("Flow root").routing() }
        }
        let child = RouteDestination(NumberedRoute.self) { _, _ in AncestorUnwindReader(recorder: recorder) }
        let routes = RootRouteMap {
            testDeclaration(parent, presentation: .init(style: style, priority: .default), children: [
                RouteScopeDeclaration(routes: testPush(child)._routeDeclarations)
            ])
        } destinations: { parent; child }
        let window = mount(WithRouter(routes: routes, router: router) { Text("Root").routing() })
        defer { close(window) }
        try #require(await waitUntil { router.engine.root.presentationHostID != nil })
        await router.default.present(DomainOnlyRoute())
        let parentScope = try #require(router.engine.defaultSpace.rootPath.last)
        try #require(await waitUntil { parentScope.isInstalledInView && parentScope.presentationHostID != nil })
        await Router(engine: router.engine, scope: parentScope).present(NumberedRoute(number: 1))
        try #require(await waitUntil { recorder.unwindRoute != nil })
        let action = try #require(recorder.unwindRoute)
        #expect(action == UnwindRouteAction(router: router.engine, routeScope: parentScope))
        if childUnwindsFirst {
            let childScope = try #require(router.engine.defaultSpace.rootPath.last)
            #expect(await UnwindRouteAction(router: router.engine, routeScope: childScope)())
            #expect(router.engine.defaultSpace.rootPath.last === parentScope)
        }
        var completed: Bool?
        let unwind = Task { completed = await action() }
        defer { unwind.cancel() }
        try #require(await waitUntil { completed != nil })
        #expect(completed == true)
        #expect(router.engine.defaultSpace.rootPath.isEmpty)
    }

    private func recorderDismiss(_ recorder: RenderedDestinationRecorder) {
        recorder.context = nil
        recorder.environment = nil
        recorder.dismiss?()
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    #if canImport(UIKit)
    private func mount(_ view: some View) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        precondition(scene != nil, "Run rendering tests in an app host with a connected window scene.")
        let window = UIWindow(windowScene: scene!)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    #else
    private func mount(_ view: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        return window
    }
    private func close(_ window: NSWindow) { window.close() }
    #endif
}

@MainActor @Observable
private final class CustomizedDestinationControl { var showsRoute = true }

@MainActor @Observable
private final class SelectionReconciliationControl {
    var showsPrimary = true
    var showsDuplicate = false
    var primary = "second"
    var duplicate = "first"
}

private struct SelectionReconciliationSources: View {
    @Bindable var control: SelectionReconciliationControl
    var body: some View {
        VStack {
            if control.showsPrimary { Text("Primary").routing(branch: $control.primary) }
            if control.showsDuplicate { Text("Duplicate").routing(branch: $control.duplicate) }
        }
    }
}

private struct ConditionalCustomizedDestination: View {
    @Bindable var control: CustomizedDestinationControl
    let destination: RouteView
    var body: some View {
        if control.showsRoute { destination }
        else { Text("Preparing customized content") }
    }
}

#if canImport(UIKit)
private extension UIWindow {
    var contentViewForLifecycleTest: UIView? { rootViewController?.view }
}
#else
private extension NSWindow {
    var contentViewForLifecycleTest: NSView? { contentView }
}
#endif

@MainActor
@Observable
private final class DestinationEnvironmentControl { var value = "initial" }

private struct DestinationEnvironmentHost: View {
    @Bindable var control: DestinationEnvironmentControl
    var body: some View {
        Text("Root")
            .routing()
            .environment(\.destinationTestValue, control.value)
    }
}

@MainActor
private final class RenderedDestinationRecorder {
    var context: RouteContext?
    var environment: EnvironmentValues?
    var values: [String] = []
    var number: Int?
    var dismiss: (() -> Void)?
    var unwindRoute: UnwindRouteAction?
}

private struct DestinationEnvironmentReader: View {
    let recorder: RenderedDestinationRecorder
    @Environment(\.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @UnwindRoute private var unwindRoute
    var body: some View {
        Text("Destination")
            .frame(width: 240, height: 160)
            .onAppear { recorder.environment = environment; recorder.unwindRoute = unwindRoute; recorder.dismiss = { dismiss() } }
            .onChange(of: environment.destinationTestValue) { _, _ in recorder.environment = environment }
    }
}

private extension EnvironmentValues {
    @Entry var destinationTestValue = "default"
}

private struct AncestorUnwindReader: View {
    let recorder: RenderedDestinationRecorder
    @UnwindRoute(DomainOnlyRoute.self) private var unwindFlow
    var body: some View {
        let action = unwindFlow
        Text("Flow child").onAppear { recorder.unwindRoute = action }
    }
}
