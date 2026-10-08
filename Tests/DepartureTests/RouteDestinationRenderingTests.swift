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
    @Test func replacementContextTracksEnvironmentAndKeepsCapturedActionsScoped() async throws {
        let router = Router()
        let engine = try #require(router.engine)
        let control = DestinationEnvironmentControl()
        let recorder = RenderedDestinationRecorder()
        let destination = RouteDestination(DomainOnlyRoute.self) { _, context in
            recorder.context = context
            recorder.values.append(context.environment.destinationTestValue)
            return DestinationEnvironmentReader(recorder: recorder)
        }
        let host = WithRouter(router: router) {
            DestinationEnvironmentHost(control: control, destination: destination)
        }
        let window = mount(host)
        defer { close(window) }
        try #require(await waitUntil { engine.root.firstRouteAttachment(for: DomainOnlyRoute.self) != nil })
        await router.present(DomainOnlyRoute())
        try #require(await waitUntil { recorder.environment != nil && recorder.context != nil })
        let firstScope = try #require(engine.normalTree.rootPath.last)
        let context = try #require(recorder.context)
        let initialValue = context.environment.destinationTestValue
        #expect(context.presentation.style == .replace)
        #expect(context.presentation.priority == .normal)
        #expect(context.router == Router(engine: engine, scope: firstScope))
        #expect(context.environment.router == context.router)
        #expect(context.environment.unwindRoute == context.unwindRoute)
        #expect(context.environment.routeScope === firstScope)
        #expect(context.environment.routePhase == .active)
        #expect(recorder.environment?.router == context.router)
        #expect(recorder.environment?.destinationTestValue == "initial")

        control.value = "updated"
        try #require(await waitUntil { recorder.context?.environment.destinationTestValue == "updated" })
        #expect(recorder.values.contains("updated"))
        #expect(initialValue == "initial")
        #expect(await context.unwindRoute())
        try #require(await waitUntil { engine.normalTree.rootPath.isEmpty })
        await router.present(DomainOnlyRoute())
        let nextScope = try #require(engine.normalTree.rootPath.last)
        #expect(nextScope !== firstScope)
        #expect(!(await context.unwindRoute()))
        await context.router.present(DomainOnlyRoute())
        #expect(engine.normalTree.rootPath.last === nextScope)
        #expect(await router.unwind(to: .root))
    }

    @Test func explicitDestinationWinsOverLegacyProvider() async throws {
        let router = Router()
        let engine = try #require(router.engine)
        let recorder = RenderedDestinationRecorder()
        let destination = RouteDestination(FeatureProvidedRoute.self) { _, context in
            recorder.context = context
            return Text("Explicit destination")
        }
        let host = WithRouter(router: router) {
            Text("Root").routes { Replace(destination) }
        }
        let window = mount(host)
        defer { close(window) }
        try #require(await waitUntil { engine.root.firstRouteAttachment(for: FeatureProvidedRoute.self) != nil })
        await router.present(FeatureProvidedRoute { recorder.legacyBuildCount += 1 })
        try #require(await waitUntil { recorder.context != nil })
        #expect(recorder.legacyBuildCount == 0)
        #expect(await router.unwind(to: .root))
    }

    @Test(arguments: [RoutePresentation.Style.push, .sheet, .cover(.slide), .cover(.fade)])
    func contextReportsMatchedPresentationStyle(style: RoutePresentation.Style) async throws {
        let router = Router()
        let engine = try #require(router.engine)
        let recorder = RenderedDestinationRecorder()
        let destination = RouteDestination(DomainOnlyRoute.self) { _, context in
            recorder.context = context
            return DestinationEnvironmentReader(recorder: recorder)
        }
        let host = WithRouter(router: router) {
            NavigationStack {
                Text("Root").routes {
                    if style == .push { Push(destination) }
                    if style == .sheet { Sheet(destination) }
                    if case .cover(let transition) = style { Cover(destination, transition: transition) }
                }
            }
            .environment(\.destinationTestValue, "local")
        } windowDestination: { destination, environment in
            destination.environment(\.destinationTestValue, environment.destinationTestValue)
        }
        let window = mount(host)
        defer { close(window) }
        try #require(await waitUntil { engine.root.firstRouteAttachment(for: DomainOnlyRoute.self) != nil })
        await router.present(DomainOnlyRoute())
        try #require(await waitUntil { recorder.context != nil && recorder.environment != nil })
        let context = try #require(recorder.context)
        #expect(context.presentation.style == style)
        #expect(context.presentation.priority == .normal)
        #expect(context.environment.destinationTestValue == "local")
        #expect(recorder.environment?.destinationTestValue == "local")
        #expect(context.environment.router == context.router)
        #expect(context.environment.unwindRoute == context.unwindRoute)
        #expect(recorder.environment?.router == context.router)
        if style == .push {
            #expect(await context.unwindRoute())
        } else {
            recorder.context = nil
            recorder.environment = nil
            recorder.dismiss?()
            try #require(await waitUntil { engine.normalTree.rootPath.isEmpty })
        }
    }

    @Test(arguments: [RoutePriority.high, .critical])
    func elevatedChildrenReceiveLocalStyleAndEffectivePriority(priority: RoutePriority) async throws {
        let router = Router()
        let engine = try #require(router.engine)
        let parentRecorder = RenderedDestinationRecorder()
        let childRecorder = RenderedDestinationRecorder()
        let child = RouteDestination(NumberedRoute.self) { route, context in
            childRecorder.context = context
            childRecorder.number = route.number
            return DestinationEnvironmentReader(recorder: childRecorder)
        }
        let parent = RouteDestination(DomainOnlyRoute.self) { _, context in
            parentRecorder.context = context
            return DestinationEnvironmentReader(recorder: parentRecorder).routes { Push(child) }
        }
        let host = WithRouter(router: router) {
            Text("Root")
                .routes { Cover(parent, priority: priority, transition: .fade) }
                .environment(\.destinationTestValue, "forwarded")
        } windowDestination: { destination, environment in
            destination.environment(\.destinationTestValue, environment.destinationTestValue)
        }
        let window = mount(host)
        defer { close(window) }
        try #require(await waitUntil { engine.root.firstRouteAttachment(for: DomainOnlyRoute.self) != nil })
        await router.present(DomainOnlyRoute())
        try #require(await waitUntil { parentRecorder.context != nil })
        let parentContext = try #require(parentRecorder.context)
        #expect(parentContext.presentation == .init(style: .cover(.fade), priority: priority))
        let parentScope = try #require(engine.routeForest.tree(for: priority)?.rootPath.last)
        try #require(await waitUntil { parentScope.firstRouteAttachment(for: NumberedRoute.self) != nil })
        await parentContext.router.present(NumberedRoute(number: 17))
        try #require(await waitUntil { childRecorder.context != nil && childRecorder.environment != nil })
        let childContext = try #require(childRecorder.context)
        #expect(childRecorder.number == 17)
        #expect(childContext.presentation == .init(style: .push, priority: priority))
        #expect(childContext.environment.destinationTestValue == "forwarded")
        #expect(childRecorder.environment?.router == childContext.router)
        #expect(await childContext.unwindRoute())
        recorderDismiss(parentRecorder)
        try #require(await waitUntil { engine.routeForest.tree(for: priority) == nil })
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

@MainActor
@Observable
private final class DestinationEnvironmentControl { var value = "initial" }

private struct DestinationEnvironmentHost: View {
    @Bindable var control: DestinationEnvironmentControl
    let destination: RouteDestination<DomainOnlyRoute>
    var body: some View {
        Text("Root")
            .routes { Replace(destination) }
            .environment(\.destinationTestValue, control.value)
    }
}

@MainActor
private final class RenderedDestinationRecorder {
    var context: RouteContext?
    var environment: EnvironmentValues?
    var values: [String] = []
    var number: Int?
    var legacyBuildCount = 0
    var dismiss: (() -> Void)?
}

private struct DestinationEnvironmentReader: View {
    let recorder: RenderedDestinationRecorder
    @Environment(\.self) private var environment
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Text("Destination")
            .frame(width: 240, height: 160)
            .onAppear { recorder.environment = environment; recorder.dismiss = { dismiss() } }
            .onChange(of: environment.destinationTestValue) { _, _ in recorder.environment = environment }
    }
}

private extension EnvironmentValues {
    @Entry var destinationTestValue = "default"
}
