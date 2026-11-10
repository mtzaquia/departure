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


    @Test func destinationUsesOneBridgeForHostRegistrationAndNativeAdmission() async throws {
        let engine = RouterEngine(routes: RootRouteMap {
            Replace(DomainOnlyRoute.self)
        } destinations: {
            RouteDestination(DomainOnlyRoute.self) { _, _ in Text("Single lifecycle source") }
        })
        engine.routeScopeDidInstallInView(engine.root)
        await engine.present(DomainOnlyRoute())
        let scope = try #require(engine.tree.rootPath.last)
        let lifetime = NativePresentationLifetime()
        lifetime.synchronize(.init(scope: scope))
        let snapshot = try #require(lifetime.presentation)
        let window = mount(RouteView(scope: snapshot.scope, nativePresentation: lifetime).environment(\.routerEngine, engine))
        defer { close(window) }
        try #require(await waitUntil { scope.isAvailableForPresentation && scope.presentationHostID != nil })
        #expect(lifecycleBridgeCount(in: try #require(window.contentViewForLifecycleTest)) == 1)
        lifetime.synchronize(nil)
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

    @Test(arguments: [RoutePresentation.Style.sheet, .cover(.fade)], [(false, false), (false, true), (true, false), (true, true)])
    func ancestorReaderDismissesItsFlow(style: RoutePresentation.Style, options: (Bool, Bool)) async throws {
        let (childUnwindsFirst, usePolicy) = options
        let router = RootRouter()
        let recorder = RenderedDestinationRecorder()
        let parent = RouteDestination(DomainOnlyRoute.self) { _, _ in
            NavigationStack { Text("Flow root").routing() }
        }
        let child = RouteDestination(NumberedRoute.self) { _, _ in
            if usePolicy { PolicyUnwindReader(recorder: recorder, target: .nearestModal) }
            else { AncestorUnwindReader(recorder: recorder) }
        }
        let routes = RootRouteMap {
            testDeclaration(parent, presentation: .init(style: style), children: [
                RouteScopeDeclaration(routes: testPush(child)._routeDeclarations)
            ])
        } destinations: { parent; child }
        let window = mount(WithRouter(routes: routes, router: router) { Text("Root").routing() })
        defer { close(window) }
        try #require(await waitUntil { router.engine.root.presentationHostID != nil })
        await router.root.present(DomainOnlyRoute())
        let parentScope = try #require(router.engine.tree.rootPath.last)
        try #require(await waitUntil { parentScope.isInstalledInView && parentScope.presentationHostID != nil })
        await Router(engine: router.engine, scope: parentScope).present(NumberedRoute(number: 1))
        try #require(await waitUntil { recorder.unwindRoute != nil })
        let action = try #require(recorder.unwindRoute)
        #expect(action == UnwindRouteAction(router: router.engine, routeScope: parentScope))
        if childUnwindsFirst {
            let childScope = try #require(router.engine.tree.rootPath.last)
            #expect(await UnwindRouteAction(router: router.engine, routeScope: childScope)())
            #expect(router.engine.tree.rootPath.last === parentScope)
        }
        var completed: Bool?
        let unwind = Task { completed = await action() }
        defer { unwind.cancel() }
        try #require(await waitUntil { completed != nil })
        #expect(completed == true)
        #expect(router.engine.tree.rootPath.isEmpty)
    }

    #if canImport(UIKit)
    @Test(arguments: Sheet.CompactAdaptation.allCases)
    func sheetCompactAdaptationChangesOnlyNativePresentation(adaptation: Sheet.CompactAdaptation) async throws {
        let router = RootRouter()
        let recorder = RenderedDestinationRecorder()
        let routes = RootRouteMap {
            Sheet(DomainOnlyRoute.self, compactAdaptation: adaptation)
        } destinations: {
            RouteDestination(DomainOnlyRoute.self) { _, context in
                NavigationStack {
                    Text("Adaptive sheet").navigationTitle("Adaptation")
                }
                .onChange(of: context.environment.routePresentation, initial: true) { _, presentation in
                    recorder.presentation = presentation
                }
            }
        }
        let window = mount(WithRouter(routes: routes, router: router) { Text("Root").routing() })
        defer { close(window) }
        try #require(await waitUntil { router.engine.root.presentationHostID != nil })
        await router.root.present(DomainOnlyRoute())
        let scope = try #require(router.engine.tree.rootPath.last)
        try #require(await waitUntil {
            scope.isInstalledInView && window.rootViewController?.presentedViewController?.isBeingPresented == false
        })
        let controller = try #require(window.rootViewController?.presentedViewController)
        let frame = controller.view.convert(controller.view.bounds, to: window)
        let compact = window.traitCollection.horizontalSizeClass == .compact
            || window.traitCollection.verticalSizeClass == .compact
        let presentation = try #require(recorder.presentation)
        #expect(presentation.effectivePresentationStyle == (adaptation == .cover && compact ? .cover(.slide) : .sheet))
        #expect(presentation.isWithinSheetRoute == !(adaptation == .cover && compact))
        #expect(!presentation.isGlobalRoute)
        if adaptation == .cover && compact {
            #expect(abs(frame.minY - window.bounds.minY) < 1)
            #expect(abs(frame.height - window.bounds.height) < 1)
        } else {
            #expect(frame.height < window.bounds.height - 1)
        }
        #expect(scope.routePresentation?.declaredStyle == .sheet)
        #expect(await UnwindRouteAction(router: router.engine, routeScope: scope)())
        #expect(router.engine.tree.rootPath.isEmpty)
    }

    @Test func repeatedFadePreservesDestinationAnimationsAndWaitsForVisibleExit() async throws {
        let router = RootRouter()
        let recorder = FadeTransactionRecorder()
        let control = FadeAnimationControl()
        let destination = RouteDestination(DomainOnlyRoute.self) { _, _ in
            NavigationStack {
                FadeTransactionProbe(control: control, recorder: recorder)
                    .navigationTitle("Fade layout")
                    .toolbar { Button("Unlock") {} }
            }
        }
        let routes = RootRouteMap {
            GlobalMap { Cover(DomainOnlyRoute.self, transition: .fade) }
        } destinations: { destination }
        let window = mount(WithRouter(routes: routes, router: router) { Text("Root").routing() })
        defer { close(window) }
        try #require(await waitUntil { router.engine.root.presentationHostID != nil })

        for _ in 0..<2 {
            recorder.animations.removeAll()
            await router.root.present(DomainOnlyRoute())
            let scope = try #require(router.engine.tree.rootPath.last)
            try #require(await waitUntil { scope.isInstalledInView && !recorder.animations.isEmpty })
            // Let the entrance settle before exercising a destination-owned animation.
            try await Task.sleep(for: .milliseconds(450))

            recorder.animations.removeAll()
            withAnimation(.linear(duration: 0.1)) { control.offset += 10 }
            try #require(await waitUntil { recorder.animations.contains { $0 != nil } })
            try await Task.sleep(for: .milliseconds(150))

            let exitStarted = ContinuousClock.now
            #expect(await UnwindRouteAction(router: router.engine, routeScope: scope)())
            // Returning immediately would tear down the native cover before its
            // opacity animation has a chance to become visible.
            #expect(ContinuousClock.now - exitStarted >= .milliseconds(150))
            #expect(router.engine.tree.rootPath.isEmpty)
        }
    }
    #endif

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
private final class RenderedDestinationRecorder {
    var unwindRoute: UnwindRouteAction?
    var presentation: RoutePresentationState?
}

private struct AncestorUnwindReader: View {
    let recorder: RenderedDestinationRecorder
    @UnwindRoute(DomainOnlyRoute.self) private var unwindFlow
    var body: some View {
        let action = unwindFlow
        Text("Flow child").onAppear { recorder.unwindRoute = action }
    }
}

private struct PolicyUnwindReader: View {
    let recorder: RenderedDestinationRecorder
    @UnwindRoute private var unwindFlow

    init(recorder: RenderedDestinationRecorder, target: Router.UnwindTarget) {
        self.recorder = recorder
        _unwindFlow = UnwindRoute(target)
    }

    var body: some View {
        let action = unwindFlow
        Text("Flow child").onAppear { recorder.unwindRoute = action }
    }
}

#if canImport(UIKit)
@MainActor @Observable
private final class FadeAnimationControl { var offset: CGFloat = 0 }

@MainActor
private final class FadeTransactionRecorder { var animations: [Animation?] = [] }

private struct FadeTransactionProbe: View {
    let control: FadeAnimationControl
    let recorder: FadeTransactionRecorder

    var body: some View {
        Text("Stable layout")
            .offset(x: control.offset)
            .transaction { recorder.animations.append($0.animation) }
    }
}
#endif
