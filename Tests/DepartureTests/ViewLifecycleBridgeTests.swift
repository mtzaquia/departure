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
import Testing
@testable import Departure

@MainActor
@Suite
struct ViewLifecycleBridgeTests {
    @Test func finalTeardownRetainsDeliveryUntilCompletionAndThenReleasesIt() async {
        var delivery: ViewLifecycleTeardownDelivery? = ViewLifecycleTeardownDelivery()
        weak let retainedDelivery = delivery
        let lifecycleID = UUID()
        var completed = false
        delivery?.install(lifecycleID)
        let teardown = delivery?.schedule(for: lifecycleID) { completed = true }
        delivery = nil
        #expect(retainedDelivery != nil)
        #expect(!completed)
        await teardown?.value
        #expect(completed)
        #expect(retainedDelivery == nil)
    }

    @Test func installedAndCreatedTeardownsRemainIndependent() async {
        let delivery = ViewLifecycleTeardownDelivery()
        let old = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let next = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        var teardownIDs: [UUID] = []
        let handler: @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void = { _, id, event in
            if case .dismantled = event { teardownIDs.append(id) }
        }
        delivery.deliver(.created, for: old, handler: handler)
        delivery.deliver(.installedInWindow(isInitial: true), for: old, handler: handler)
        let installed = delivery.deliver(.dismantled, for: old, handler: handler)
        delivery.deliver(.created, for: next, handler: handler)
        let created = delivery.deliver(.dismantled, for: next, handler: handler)
        await installed?.value
        await created?.value
        #expect(Set(teardownIDs) == [old.id, next.id])
        #expect(teardownIDs.count == 2)
    }

    @Test(arguments: [false, true])
    func installationCancelsCreatedTeardownOnlyForTheSameBridge(sameBridge: Bool) async {
        let delivery = ViewLifecycleTeardownDelivery()
        let created = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let other = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        var teardownIDs: [UUID] = []
        let handler: @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void = { _, id, event in
            if case .dismantled = event { teardownIDs.append(id) }
        }
        delivery.deliver(.created, for: created, handler: handler)
        let teardown = delivery.deliver(.dismantled, for: created, handler: handler)
        delivery.deliver(.installedInWindow(isInitial: true), for: sameBridge ? created : other, handler: handler)
        await teardown?.value
        #expect(teardownIDs == (sameBridge ? [] : [created.id]))
    }

    @Test func recreatedOffWindowBridgeKeepsItsRoutingRegistrationUntilItsOwnTeardown() async {
        let engine = RouterEngine()
        let attachment = RouteScopeAttachment(kind: .routes)
        let delivery = ViewLifecycleTeardownDelivery()
        let hostID = RoutePresentationHostID()
        let old = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let next = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [], backing: .buffered, defer: false)
        window.contentView = old
        engine.root.ledger.installManagedView(old, id: old.id)
        engine.routeScopeDidInstallInView(engine.root)
        let handler: @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void = { view, id, event in
            attachment.handle(event, id: id, target: engine.root, view: view,
                apply: { $0.installRouteDeclarations(sourceID: attachment.id, id: nil, branchSelection: nil,
                    routeDeclarations: [RouteScopeDeclaration(routes: Sheet(MessageRoute.self)._routeDeclarations.hosted(by: hostID))]) },
                remove: { $0.uninstallRouteDeclarations(sourceID: attachment.id) })
        }
        delivery.deliver(.installedInWindow(isInitial: true), for: old, handler: handler)
        #expect(engine.root.ledger.routeDeclarations.count == 1)
        let stale = delivery.deliver(.dismantled, for: old, handler: handler)
        delivery.deliver(.created, for: next, handler: handler)
        engine.root.ledger.uninstallManagedView(id: old.id)
        engine.routeScopeDidLeaveView(engine.root)
        delivery.deliver(.updated(isInstalledInWindow: false), for: next, handler: handler)
        await stale?.value
        #expect(!engine.root.isInstalledInView)
        #expect(engine.root.ledger.routeDeclarations.count == 1)
        let teardown = delivery.deliver(.dismantled, for: next, handler: handler)
        await teardown?.value
        #expect(engine.root.ledger.routeDeclarations.isEmpty)
    }

    @Test func creationOfAnUninstalledReplacementDoesNotSuppressTheInstalledHostsTeardown() async {
        let delivery = ViewLifecycleTeardownDelivery()
        let engine = RouterEngine()
        let old = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let next = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let handler: @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void = { view, id, event in
            handleHostEvent(event, in: engine, view: view, id: id)
        }
        delivery.deliver(.installedInWindow(isInitial: true), for: old, handler: handler)
        #expect(engine.root.isInstalledInView)
        let teardown = delivery.deliver(.dismantled, for: old, handler: handler)
        delivery.deliver(.created, for: next, handler: handler)
        await teardown?.value
        #expect(!engine.root.isInstalledInView)
    }

    @Test func creationOfANewerPreparationCoalescesUninstalledTeardown() async {
        let delivery = ViewLifecycleTeardownDelivery()
        let old = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let next = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        var teardowns: [UUID] = []
        let handler: @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void = { _, id, event in
            if case .dismantled = event { teardowns.append(id) }
        }
        delivery.deliver(.created, for: old, handler: handler)
        let stale = delivery.deliver(.dismantled, for: old, handler: handler)
        delivery.deliver(.created, for: next, handler: handler)
        #expect(stale?.isCancelled == true)
        await stale?.value
        #expect(teardowns.isEmpty)
        let final = delivery.deliver(.dismantled, for: next, handler: handler)
        await final?.value
        #expect(teardowns == [next.id])
    }

    @Test func staleTeardownCannotCancelTheCurrentHostsTeardown() async {
        let delivery = ViewLifecycleTeardownDelivery()
        let old = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let current = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        var teardownIDs: [UUID] = []
        let handler: @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void = { _, id, event in
            if case .dismantled = event { teardownIDs.append(id) }
        }
        delivery.deliver(.installedInWindow(isInitial: true), for: old, handler: handler)
        delivery.deliver(.installedInWindow(isInitial: true), for: current, handler: handler)
        let teardown = delivery.deliver(.dismantled, for: current, handler: handler)
        delivery.deliver(.dismantled, for: old, handler: handler)
        await teardown?.value
        #expect(teardownIDs == [current.id])
    }

    @Test func creationDeliversTeardownBeforeWindowInstallationWithoutMakingTheHostReady() async {
        let delivery = ViewLifecycleTeardownDelivery()
        let engine = RouterEngine()
        let view = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        var teardowns = 0
        let handler: @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void = { view, id, event in
            handleHostEvent(event, in: engine, view: view, id: id)
            if case .dismantled = event { teardowns += 1 }
        }
        delivery.deliver(.created, for: view, handler: handler)
        #expect(!engine.root.isInstalledInView)
        #expect(view.window == nil)
        let teardown = delivery.deliver(.dismantled, for: view, handler: handler)
        await teardown?.value
        #expect(teardowns == 1)
        #expect(!engine.root.isInstalledInView)
    }

    private func handleHostEvent(_ event: ViewLifecycleBridge.Event, in engine: RouterEngine,
        view: PlatformView?, id: UUID) {
        switch event {
        case .created, .updated(isInstalledInWindow: false): break
        case .installedInWindow, .updated(isInstalledInWindow: true):
            if let view { engine.root.ledger.installManagedView(view, id: id) }
            engine.routeScopeDidInstallInView(engine.root)
        case .dismantled, .deinitialized:
            engine.root.ledger.uninstallManagedView(id: id)
            engine.routeScopeDidLeaveView(engine.root)
        }
    }

    @Test func transientWindowRemovalDoesNotEmitLifecycleEvents() {
        var events: [ViewLifecycleBridge.Event] = []
        let view = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, event in
            events.append(event)
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView()

        window.contentView?.addSubview(view)
        #expect(view.window === window)

        view.removeFromSuperview()
        #expect(view.window == nil)

        window.contentView?.addSubview(view)
        #expect(view.window === window)

        #expect(events.dismantledCount == 0)
        #expect(events.installedInWindowCount == 2)
    }

    @Test func stableWindowRemovalDoesNotEmitLifecycleEvents() {
        var events: [ViewLifecycleBridge.Event] = []
        let view = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, event in
            events.append(event)
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView()

        window.contentView?.addSubview(view)
        view.removeFromSuperview()

        #expect(events.dismantledCount == 0)
        #expect(events.installedInWindowCount == 1)
    }

    @Test func dismantleEmitsDismantledOnce() {
        var events: [ViewLifecycleBridge.Event] = []
        let view = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, event in
            events.append(event)
        })

        ViewLifecycleBridge.dismantleNSView(view, coordinator: ())
        ViewLifecycleBridge.dismantleNSView(view, coordinator: ())

        #expect(events.dismantledCount == 1)
    }

    @Test func teardownDeliveryDefersWorkUntilAfterTheCurrentMainActorTurn() async {
        let delivery = ViewLifecycleTeardownDelivery()
        let lifecycleID = UUID()
        var didRun = false
        delivery.install(lifecycleID)

        let task = delivery.schedule(for: lifecycleID) {
            didRun = true
        }

        #expect(didRun == false)
        await task?.value
        #expect(didRun)
    }

    @Test func teardownDeliveryCoalescesRepeatedEvents() async {
        let delivery = ViewLifecycleTeardownDelivery()
        let lifecycleID = UUID()
        var deliveredValues: [Int] = []
        delivery.install(lifecycleID)

        let firstTask = delivery.schedule(for: lifecycleID) {
            deliveredValues.append(1)
        }
        let secondTask = delivery.schedule(for: lifecycleID) {
            deliveredValues.append(2)
        }
        await firstTask?.value
        await secondTask?.value

        #expect(deliveredValues == [2])
    }

    @Test(arguments: [false, true]) func installationCancelsDeferredTeardown(reinstallSameView: Bool) async {
        let delivery = ViewLifecycleTeardownDelivery()
        let removedLifecycleID = UUID()
        let installedLifecycleID = reinstallSameView ? removedLifecycleID : UUID()
        var didRun = false
        delivery.install(removedLifecycleID)

        let task = delivery.schedule(for: removedLifecycleID) {
            didRun = true
        }
        delivery.install(installedLifecycleID)

        #expect(task?.isCancelled == true)
        await task?.value
        #expect(didRun == false)

        let staleTask = delivery.schedule(for: UUID()) {
            didRun = true
        }
        await staleTask?.value
        #expect(didRun == false)
    }

    @Test func identifiedTeardownIsCoalescedWithRegistrationTeardown() async {
        let delivery = ViewLifecycleTeardownDelivery()
        let replacedView = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        let replacementView = ViewLifecycleBridge.LifecycleView(onIdentifiedEvent: { _, _ in })
        var identifiedTeardowns = 0
        var teardownIDs: [UUID] = []
        let handler: @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void = { view, id, event in
            if case .dismantled = event {
                #expect(view == nil)
                identifiedTeardowns += 1
                teardownIDs.append(id)
            }
        }

        delivery.deliver(.installedInWindow(isInitial: true), for: replacedView,
            handler: handler)
        let teardown = delivery.deliver(.dismantled, for: replacedView,
            handler: handler)
        delivery.deliver(.installedInWindow(isInitial: true), for: replacementView,
            handler: handler)

        await teardown?.value
        #expect(identifiedTeardowns == 0)

        let finalTeardown = delivery.deliver(.dismantled, for: replacementView,
            handler: handler)
        await finalTeardown?.value
        #expect(identifiedTeardowns == 1)
        #expect(teardownIDs == [replacementView.id])
    }
}

private extension [ViewLifecycleBridge.Event] {
    var installedInWindowCount: Int {
        count { event in
            if case .installedInWindow = event {
                return true
            }

            return false
        }
    }

    var dismantledCount: Int {
        count { event in
            if case .dismantled = event {
                return true
            }

            return false
        }
    }
}
#endif
