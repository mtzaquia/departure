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

#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import Departure

@MainActor
// Window startup can block the main actor long enough to exhaust unrelated unit-test
// polling windows. Run this suite separately with DEPARTURE_RUN_HOSTED_UI_TESTS=1
// and --filter MacOSPresentationTests.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DEPARTURE_RUN_HOSTED_UI_TESTS"] == "1"))
struct MacOSPresentationTests {
    @Test func modalUnwindWaitsForNativeDismissalCompletion() async throws {
        let owner = RootRouter()
        let host = WithRouter(routes: RootRouteMap {
            Sheet(RouteDestination(SettingsRoute.self) { _, _ in Text("Native modal") })
        }, router: owner) { Text("Root") }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.orderFront(nil)
        defer { window.close() }
        try #require(await waitUntil { owner.engine.root.isInstalledInView })
        await owner.current.present(SettingsRoute())
        let modal = try #require(owner.engine.defaultSpace.rootPath.last)
        try #require(await waitUntil { modal.isInstalledInView && window.attachedSheet != nil })
        #expect(await owner.current.unwind(to: .topmostAncestor))
        #expect(owner.engine.defaultSpace.rootPath.isEmpty)
        #expect(window.attachedSheet == nil)
        #expect(!owner.engine.isNavigating)
    }

    @Test func branchLocalDeclarationsRemainAttachedToTheirBranch() async throws {
        let router = RootRouter()
        let host = WithRouter(routes: RootRouteMap { Branches { Branch("detail") { Push(RouteDestination(MacOSPresentingRoute.self) { route, _ in route.destination() }) } } }, router: router) {
            Text("Branch content")
                .routing()
                .routing("detail")
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.orderFront(nil)
        defer { window.close() }

        try #require(await waitUntil {
            router.engine.root.branchScopes["detail"]?
                .definitions.routeBinding(for: MacOSPresentingRoute.self) != nil
        })
        #expect(router.engine.root.definitions.routeBinding(for: MacOSPresentingRoute.self) == nil)
    }

    @Test func nonDeparturePresentationCannotReplacePresentingBranchDeclarations() async throws {
        let router = RootRouter()
        let control = MacOSLegacyPresentationControl()
        let host = WithRouter(routes: RootRouteMap { Push(RouteDestination(MacOSPresentingRoute.self) { route, _ in route.destination() }) }, router: router) {
            MacOSLegacyPresentationHost(control: control)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.orderFront(nil)
        defer { window.close() }

        try #require(await waitUntil {
            router.engine.root.definitions.routeBinding(for: MacOSPresentingRoute.self) != nil
        })

        control.showsSheet = true
        try #require(await waitUntil { window.attachedSheet != nil })

        #expect(router.engine.root.definitions.routeBinding(for: MacOSPresentingRoute.self) != nil)
        #expect(router.engine.root.definitions.routeBinding(for: MacOSPresentedOnlyRoute.self) == nil)
        #expect(router.engine.root.hookBinding(
            for: .actionInterceptor(ObjectIdentifier(ContextProbeAction.self)), in: router.engine.spaces
        ) == nil)
        #expect(router.engine.root.branchScopes["home"] == nil)

        control.showsSheet = false
        try #require(await waitUntil { window.attachedSheet == nil })
        #expect(router.engine.root.definitions.routeBinding(for: MacOSPresentingRoute.self) != nil)
    }

    @Test func replacementPreservesBranchSourceEnvironmentAndContextualDestination() async throws {
        let router = RootRouter()
        let engine = router.engine
        let recorder = MacOSScopeRecorder()
        let destinationRecorder = MacOSScopeRecorder()
        let host = WithRouter(routes: RootRouteMap { Branches(concurrent: true) { Branch("detail") { Replace(RouteDestination(MacOSScopedReplacementRoute.self) { route, _ in route.destination() }) } } }, router: router) {
            MacOSScopeReader(recorder: recorder)
                .routing("detail")
                .routing()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.orderFront(nil)
        defer { window.close() }

        try #require(await waitUntil { engine.root.branchScopes["detail"] != nil && recorder.scope != nil })
        let branch = try #require(engine.root.branchScopes["detail"])
        #expect(branch.parent === engine.root)
        #expect(branch.sourceEnvironment.routeScope === branch)
        #expect(branch.sourceEnvironment.router == Router(engine: engine, scope: branch))
        #expect(recorder.scope === branch)
        #expect(recorder.router == Router(engine: engine, scope: branch))

        await router.current.branch("detail").present(MacOSScopedReplacementRoute(recorder: destinationRecorder))
        let selected = try #require(branch.path.last)
        try #require(await waitUntil { destinationRecorder.scope === selected && destinationRecorder.isVisible })
        #expect(destinationRecorder.router == Router(engine: engine, scope: selected))
        #expect(engine.root.branchScopes["detail"] === branch)
        #expect(branch.sourceEnvironment.routeScope === branch)
        #expect(branch.sourceEnvironment.router == Router(engine: engine, scope: branch))
        #expect(branch.routeAttachments.count == 1)
    }

    @Test func inlineReplacementNeedsNoNavigationStackAndKeepsItsDeclarationHost() async throws {
        let router = RootRouter()
        let recorder = MacOSInlineRecorder()
        let control = MacOSInlineControl()
        let host = WithRouter(routes: RootRouteMap { Replace(RouteDestination(MacOSInlineRoute.self) { route, _ in route.destination() }) }, router: router) {
            MacOSInlinePlaceholder(control: control)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.orderFront(nil)
        defer { window.close() }

        let installed = await waitUntil { !router.engine.root.routeAttachments.isEmpty }
        try #require(installed)
        await router.current.present(MacOSInlineRoute(number: 1, recorder: recorder))
        let first = await waitUntil { recorder.number == 1 }
        try #require(first)
        await router.current.present(MacOSInlineRoute(number: 2, recorder: recorder))
        let second = await waitUntil { recorder.number == 2 }
        try #require(second)
        #expect(router.engine.root.routeAttachments.count == 1)
        #expect(router.engine.defaultSpace.rootPath.count == 1)
        #expect(window.attachedSheet == nil)
        control.isEnabled = false
        #expect(router.engine.defaultSpace.rootPath.count == 1)
        #expect(recorder.number == 2)
        #expect(router.engine.root.routeAttachments.count == 1)
        control.isEnabled = true
        let restored = await waitUntil { router.engine.root.routeAttachments.count == 1 }
        try #require(restored)
        await router.current.present(MacOSInlineRoute(number: 3, recorder: recorder))
        let third = await waitUntil { recorder.number == 3 }
        try #require(third)
        #expect(await router.current.unwind(to: .root))
        #expect(recorder.number == nil)
        #expect(router.engine.root.routeAttachments.count == 1)
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func elevatedFadeCoverPresentsAndDismissesAsSheet(priority: RoutePriority) async throws {
        let router = RouterEngine()
        let recorder = MacOSDismissRecorder()
        let host = WithRouter(routes: RootRouteMap {} highPriority: { if priority == .high { Cover(RouteDestination(MacOSFadeRoute.self) { route, _ in route.destination() }, transition: .fade) } } criticalPriority: { if priority == .critical { Cover(RouteDestination(MacOSFadeRoute.self) { route, _ in route.destination() }, transition: .fade) } }, router: RootRouter(engine: router)) {
            Color.clear.frame(width: 320, height: 240)
                .routing()
        } windowDestination: { destination, _ in
            destination
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.orderFront(nil)
        defer { window.close() }

        let installed = await waitUntil { !router.root.routeAttachments.isEmpty }
        try #require(installed)
        await router.present(MacOSFadeRoute(recorder: recorder))
        let presented = await waitUntil { window.attachedSheet != nil && recorder.dismiss != nil }
        #expect(presented)
        #expect(router.spaces.space(for: priority) != nil)
        recorder.dismiss?()
        let dismissed = await waitUntil {
            window.attachedSheet == nil && router.spaces.space(for: priority) == nil
        }
        #expect(dismissed)
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

@MainActor
private final class MacOSInlineRecorder { var number: Int? }

@MainActor
private final class MacOSScopeRecorder {
    var scope: RouteScope?
    var router: Router?
    var isVisible = false
}

private struct MacOSScopeReader: View {
    let recorder: MacOSScopeRecorder
    @Environment(\.routeScope) private var scope
    @Environment(\.router) private var router
    var body: some View {
        Text("Scope").frame(width: 320, height: 240)
            .onAppear { recorder.scope = scope; recorder.router = router; recorder.isVisible = true }
            .onDisappear { recorder.isVisible = false }
    }
}

private struct MacOSScopedReplacementRoute: Route {
    let recorder: MacOSScopeRecorder
    func destination() -> some View { MacOSScopeReader(recorder: recorder) }
}

@MainActor
@Observable
private final class MacOSInlineControl { var isEnabled = true }

@MainActor
@Observable
private final class MacOSLegacyPresentationControl { var showsSheet = false }

private struct MacOSLegacyPresentationHost: View {
    @Bindable var control: MacOSLegacyPresentationControl

    var body: some View {
        Text("Presenting content")
            .frame(width: 320, height: 240)
            .sheet(isPresented: $control.showsSheet) {
                VStack {
                    Text("Non-Departure sheet")
                        .routing()
                        .hooks {
                            ActionInterceptor(ContextProbeAction.self) { _ in }
                        }
                    Text("Non-Departure branch")
                        .routing("home")
                }
            }
            .routing()
    }
}

private struct MacOSPresentingRoute: Route {
    func destination() -> some View { Text("Presenting route") }
}

private struct MacOSPresentedOnlyRoute: Route {
    func destination() -> some View { Text("Presented-only route") }
}

private struct MacOSInlinePlaceholder: View {
    let control: MacOSInlineControl
    var body: some View {
        Text("Placeholder").frame(width: 320, height: 240)
            .id(control.isEnabled)
            .routing()
    }
}

private struct MacOSInlineRoute: Route {
    let number: Int
    let recorder: MacOSInlineRecorder
    func destination() -> some View {
        Text("Selected \(number)").frame(width: 320, height: 240)
            .onAppear { recorder.number = number }
            .onDisappear { if recorder.number == number { recorder.number = nil } }
    }
}

@MainActor
private final class MacOSDismissRecorder {
    var dismiss: (() -> Void)?
}

private struct MacOSFadeRoute: Route {
    let recorder: MacOSDismissRecorder
    func destination() -> some View { MacOSFadeDestination(recorder: recorder) }
}

private struct MacOSFadeDestination: View {
    let recorder: MacOSDismissRecorder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text("Fade cover").frame(width: 240, height: 160)
            .onAppear { recorder.dismiss = { dismiss() } }
    }
}
#endif
