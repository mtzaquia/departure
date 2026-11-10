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

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
// UIKit rendering requires an app-hosted test target with a connected window scene.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["DEPARTURE_RUN_HOSTED_UI_TESTS"] == "1"))
struct RoutePresentationEnvironmentTests {
    @Test func destinationsReceiveLivePresentationAndModalAncestry() async throws {
        let owner = RootRouter()
        let recorder = PresentationRecorder()
        let routes = RootRouteMap {
            GlobalMap {
                Sheet(PresentationSheetRoute.self, compactAdaptation: .cover) {
                    Push(PresentationFirstRoute.self) {
                        Push(PresentationSecondRoute.self) {
                            Cover(PresentationCoverRoute.self, transition: .fade) {
                                Replace(PresentationReplacementRoute.self)
                            }
                        }
                    }
                }
            }
        } destinations: {
            RouteDestination(PresentationSheetRoute.self) { _, context in
                NavigationStack {
                    PresentationReader(name: "sheet", recorder: recorder, context: context.environment.routePresentation)
                        .routing()
                }
            }
            RouteDestination(PresentationFirstRoute.self) { _, context in
                PresentationReader(name: "first", recorder: recorder, context: context.environment.routePresentation)
            }
            RouteDestination(PresentationSecondRoute.self) { _, context in
                PresentationReader(name: "second", recorder: recorder, context: context.environment.routePresentation)
            }
            RouteDestination(PresentationCoverRoute.self) { _, context in
                PresentationReader(name: "cover", recorder: recorder, context: context.environment.routePresentation)
            }
            RouteDestination(PresentationReplacementRoute.self) { _, context in
                PresentationReader(name: "replacement", recorder: recorder, context: context.environment.routePresentation)
            }
        }
        let root = WithRouter(routes: routes, router: owner) {
            PresentationReader(name: "root", recorder: recorder)
        }
        let host = PresentationTestHost(root)
        defer { host.close() }
        try #require(await waitUntil { recorder.views["root"] == RoutePresentationState() })

        await owner.current.present(PresentationSheetRoute())
        try #require(await waitUntil { recorder.matches("sheet", style: .sheet, withinSheet: true, global: true) })
        await owner.current.present(PresentationFirstRoute())
        try #require(await waitUntil { recorder.matches("first", style: .push, withinSheet: true) },
                     "Views: \(recorder.views); contexts: \(recorder.contexts)")
        await owner.current.present(PresentationSecondRoute())
        try #require(await waitUntil { recorder.matches("second", style: .push, withinSheet: true) })

        #if canImport(UIKit)
        // Change the presenter's traits while retaining the same sheet and pushes.
        // The presented sheet may have compact content even when its presenter is regular.
        let sheetScope = try #require(owner.engine.tree.rootPath.first)
        let pushedScope = try #require(owner.engine.tree.rootPath.last)
        host.controller.traitOverrides.horizontalSizeClass = .compact
        try #require(await waitUntil {
            recorder.matches("sheet", style: .cover(.slide), withinSheet: false, global: true)
                && recorder.matches("second", style: .push, withinSheet: false)
        }, "Views: \(recorder.views); contexts: \(recorder.contexts)")
        host.controller.traitOverrides.horizontalSizeClass = .regular
        try #require(await waitUntil { recorder.matches("second", style: .push, withinSheet: true) })
        host.controller.traitOverrides.verticalSizeClass = .compact
        try #require(await waitUntil { recorder.matches("second", style: .push, withinSheet: false) })
        host.controller.traitOverrides.verticalSizeClass = .regular
        try #require(await waitUntil {
            recorder.matches("sheet", style: .sheet, withinSheet: true, global: true)
                && recorder.matches("second", style: .push, withinSheet: true)
        })
        #expect(owner.engine.tree.rootPath.first === sheetScope)
        #expect(owner.engine.tree.rootPath.last === pushedScope)

        // Offscreen NavigationStack destinations defer their view callbacks.
        // Once revealed, the retained first screen must read the current value.
        host.controller.traitOverrides.horizontalSizeClass = .compact
        try #require(await waitUntil { recorder.matches("second", style: .push, withinSheet: false) })
        #expect(await owner.current.unwind(.current))
        try #require(await waitUntil { recorder.matches("first", style: .push, withinSheet: false) })
        host.controller.traitOverrides.horizontalSizeClass = .regular
        try #require(await waitUntil { recorder.matches("first", style: .push, withinSheet: true) })
        await owner.current.present(PresentationSecondRoute())
        try #require(await waitUntil { recorder.matches("second", style: .push, withinSheet: true) })
        #endif

        await owner.current.present(PresentationCoverRoute())
        #if canImport(UIKit)
        let coverStyle: RoutePresentation.Style = .cover(.fade)
        let coverIsSheet = false
        #else
        let coverStyle: RoutePresentation.Style = .sheet
        let coverIsSheet = true
        #endif
        try #require(await waitUntil { recorder.matches("cover", style: coverStyle, withinSheet: coverIsSheet) })
        await owner.current.present(PresentationReplacementRoute())
        try #require(await waitUntil { recorder.matches("replacement", style: .replace, withinSheet: coverIsSheet) })
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private struct PresentationSheetRoute: Route {}
private struct PresentationFirstRoute: Route {}
private struct PresentationSecondRoute: Route {}
private struct PresentationCoverRoute: Route {}
private struct PresentationReplacementRoute: Route {}

@MainActor private final class PresentationRecorder {
    var views: [String: RoutePresentationState] = [:]
    var contexts: [String: RoutePresentationState] = [:]

    func matches(_ name: String, style: RoutePresentation.Style, withinSheet: Bool, global: Bool = false) -> Bool {
        let expected = RoutePresentationState(effectivePresentationStyle: style,
                                              isWithinSheetRoute: withinSheet, isGlobalRoute: global)
        return views[name] == expected && contexts[name] == expected
    }
}

private struct PresentationReader: View {
    let name: String
    let recorder: PresentationRecorder
    var context: RoutePresentationState?
    @Environment(\.routePresentation) private var presentation

    var body: some View {
        Text(name)
            .frame(minWidth: 200, minHeight: 150)
            .onChange(of: presentation, initial: true) { _, value in recorder.views[name] = value }
            .onChange(of: context, initial: true) { _, value in recorder.contexts[name] = value }
    }
}

@MainActor private final class PresentationTestHost<Content: View> {
    #if canImport(UIKit)
    let controller: UIHostingController<Content>
    private let window: UIWindow

    init(_ content: Content) {
        controller = UIHostingController(rootView: content)
        controller.traitOverrides.horizontalSizeClass = .regular
        controller.traitOverrides.verticalSizeClass = .regular
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        precondition(scene != nil, "Run rendering tests in an app host with a connected window scene.")
        window = UIWindow(windowScene: scene!)
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
    }
    #else
    private let window: NSWindow

    init(_ content: Content) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.orderFront(nil)
    }

    func close() { window.close() }
    #endif
}
