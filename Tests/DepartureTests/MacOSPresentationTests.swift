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
    @Test func branchLocalDeclarationsRemainAttachedToTheirBranch() async throws {
        let router = Router()
        let host = WithRouter(router: router) {
            Text("Branch content")
                .routes { Push(MacOSPresentingRoute.self) }
                .routeBranch("detail")
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
            router.engine!.root.branchScopes["detail"]?
                .firstRouteAttachment(for: MacOSPresentingRoute.self) != nil
        })
        #expect(router.engine!.root.firstRouteAttachment(for: MacOSPresentingRoute.self) == nil)
    }

    @Test func nonDeparturePresentationCannotReplacePresentingBranchDeclarations() async throws {
        let router = Router()
        let control = MacOSLegacyPresentationControl()
        let host = WithRouter(router: router) {
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
            router.engine!.root.firstRouteAttachment(for: MacOSPresentingRoute.self) != nil
        })

        control.showsSheet = true
        try #require(await waitUntil { window.attachedSheet != nil })

        #expect(router.engine!.root.firstRouteAttachment(for: MacOSPresentingRoute.self) != nil)
        #expect(router.engine!.root.firstRouteAttachment(for: MacOSPresentedOnlyRoute.self) == nil)
        #expect(router.engine!.root.hookAttachments.isEmpty)
        #expect(router.engine!.root.branchScopes["home"] == nil)

        control.showsSheet = false
        try #require(await waitUntil { window.attachedSheet == nil })
        #expect(router.engine!.root.firstRouteAttachment(for: MacOSPresentingRoute.self) != nil)
    }

    @Test func replacementPreservesBranchSourceEnvironmentAndContextualDestination() async throws {
        let router = Router()
        let engine = router.engine!
        let recorder = MacOSScopeRecorder()
        let host = WithRouter(router: router) {
            MacOSScopeReader(recorder: recorder)
                .routeBranch("detail")
                .routes(branch: .constant("detail"), concurrent: true) {
                    Branch("detail") { Replace(MacOSScopedReplacementRoute.self) }
                }
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
        #expect(branch.sourceEnvironment.routeScope === engine.root)
        #expect(branch.sourceEnvironment.router == Router(engine: engine, scope: engine.root))
        #expect(recorder.scope === branch)
        #expect(recorder.router == Router(engine: engine, scope: branch))

        await router.branch("detail").present(MacOSScopedReplacementRoute(recorder: recorder))
        let selected = try #require(branch.path.last)
        try #require(await waitUntil { recorder.scope === selected })
        #expect(recorder.router == Router(engine: engine, scope: selected))
        #expect(engine.root.branchScopes["detail"] === branch)
        #expect(branch.sourceEnvironment.routeScope === engine.root)
        #expect(branch.sourceEnvironment.router == Router(engine: engine, scope: engine.root))
        #expect(engine.root.routeAttachments.count == 1)
    }

    @Test func inlineReplacementNeedsNoNavigationStackAndKeepsItsDeclarationHost() async throws {
        let router = Router()
        let recorder = MacOSInlineRecorder()
        let control = MacOSInlineControl()
        let host = WithRouter(router: router) {
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

        let installed = await waitUntil { !router.engine!.root.routeAttachments.isEmpty }
        try #require(installed)
        await router.present(MacOSInlineRoute(number: 1, recorder: recorder))
        let first = await waitUntil { recorder.number == 1 }
        try #require(first)
        await router.present(MacOSInlineRoute(number: 2, recorder: recorder))
        let second = await waitUntil { recorder.number == 2 }
        try #require(second)
        #expect(router.engine!.root.routeAttachments.count == 1)
        #expect(router.engine!.normalTree.rootPath.count == 1)
        #expect(window.attachedSheet == nil)
        control.isEnabled = false
        let cleared = await waitUntil {
            router.engine!.normalTree.rootPath.isEmpty && recorder.number == nil
                && router.engine!.root.routeAttachments.isEmpty
        }
        try #require(cleared)
        control.isEnabled = true
        let restored = await waitUntil { router.engine!.root.routeAttachments.count == 1 }
        try #require(restored)
        await router.present(MacOSInlineRoute(number: 3, recorder: recorder))
        let third = await waitUntil { recorder.number == 3 }
        try #require(third)
        #expect(await router.unwind(to: .root))
        #expect(recorder.number == nil)
        #expect(router.engine!.root.routeAttachments.count == 1)
    }

    @Test func legacyEnvironmentReadsTheUnscopedRouter() async throws {
        let router = Router()
        let engine = router.engine!
        let child = RouteScope(id: "child", route: nil)
        let local = Router(engine: engine, scope: child)
        let recorder = LegacyRouterRecorder()
        let host = WithRouter(router: router) {
            VStack {
                LegacyRouterReader(recorder: recorder, expectedLegacy: router,
                    expectedContextual: Router(engine: engine, scope: engine.root))
                LegacyRouterReader(recorder: recorder, expectedLegacy: router,
                    expectedContextual: local)
                    .environment(\.router, local)
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.orderFront(nil)
        defer { window.close() }

        let installed = await waitUntil { recorder.matches.count == 2 }
        try #require(installed)
        #expect(recorder.matches.allSatisfy { $0 })
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func elevatedFadeCoverPresentsAndDismissesAsSheet(priority: RoutePriority) async throws {
        let router = RouterEngine()
        let recorder = MacOSDismissRecorder()
        let host = WithRouter(router: Router(engine: router, scope: router.root)) {
            Color.clear.frame(width: 320, height: 240)
                .routes {
                    Cover(MacOSFadeRoute.self, priority: priority, transition: .fade)
                }
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
        #expect(router.routeForest.tree(for: priority) != nil)
        recorder.dismiss?()
        let dismissed = await waitUntil {
            window.attachedSheet == nil && router.routeForest.tree(for: priority) == nil
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
private final class LegacyRouterRecorder {
    var matches: [Bool] = []
}

@MainActor
private final class MacOSInlineRecorder { var number: Int? }

@MainActor
private final class MacOSScopeRecorder {
    var scope: RouteScope?
    var router: Router?
}

private struct MacOSScopeReader: View {
    let recorder: MacOSScopeRecorder
    @Environment(\.routeScope) private var scope
    @Environment(\.router) private var router
    var body: some View {
        Text("Scope").frame(width: 320, height: 240)
            .onAppear { recorder.scope = scope; recorder.router = router }
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
                        .routes {
                            Push(MacOSPresentedOnlyRoute.self)
                        }
                        .hooks {
                            ActionInterceptor(ContextProbeAction.self) { _ in }
                        }
                    Text("Non-Departure branch")
                        .routeBranch("home")
                }
            }
            .routes(branch: .constant("home")) {
                Branch("home") {
                    Push(MacOSPresentingRoute.self)
                }
            }
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
            .routes { if control.isEnabled { Replace(MacOSInlineRoute.self) } }
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

private struct LegacyRouterReader: View {
    // Deliberately exercises the deprecated public spelling for compatibility.
    @Environment(Router.self) private var legacyRouter
    @Environment(\.router) private var contextualRouter
    let recorder: LegacyRouterRecorder
    let expectedLegacy: Router
    let expectedContextual: Router

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .onAppear {
                recorder.matches.append(legacyRouter == expectedLegacy && contextualRouter == expectedContextual)
            }
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
