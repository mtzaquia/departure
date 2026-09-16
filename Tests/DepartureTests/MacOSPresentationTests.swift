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
    @Test func legacyEnvironmentReadsTheSameContextualRouter() async throws {
        let router = Router()
        let engine = router.engine!
        let child = RouteScope(id: "child", route: nil)
        let local = Router(engine: engine, scope: child)
        let recorder = LegacyRouterRecorder()
        let host = WithRouter(router: router) {
            VStack {
                LegacyRouterReader(recorder: recorder, expected: router)
                LegacyRouterReader(recorder: recorder, expected: local)
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

private struct LegacyRouterReader: View {
    // Deliberately exercises the deprecated public spelling for compatibility.
    @Environment(Router.self) private var legacyRouter
    @Environment(\.router) private var contextualRouter
    let recorder: LegacyRouterRecorder
    let expected: Router

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .onAppear {
                recorder.matches.append(legacyRouter == contextualRouter && legacyRouter == expected)
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
