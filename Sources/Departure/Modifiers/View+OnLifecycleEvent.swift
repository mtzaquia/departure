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

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformView = UIView
#else
import AppKit
typealias PlatformView = NSView
#endif

extension View {
    func onLifecycleEvent(
        _ handler: @escaping @MainActor (
            ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event
        ) -> Void
    ) -> some View {
        modifier(ViewLifecycleEventModifier(handler: handler))
    }
}

private struct ViewLifecycleEventModifier: ViewModifier {
    let handler: @MainActor (
        ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event
    ) -> Void

    @State private var teardownDelivery = ViewLifecycleTeardownDelivery()

    func body(content: Content) -> some View {
        content.background {
            ViewLifecycleBridge(onIdentifiedEvent: { lifecycleView, event in
                teardownDelivery.deliver(event, for: lifecycleView, handler: handler)
            })
            .frame(width: 0, height: 0)
        }
    }
}

/// Moves teardown out of SwiftUI's representable dismantle stack.
/// A later installation invalidates pending work so transient bridge replacement cannot
/// uninstall a live registration.
/// Pending callbacks retain delivery until the router receives its final teardown.
final class ViewLifecycleTeardownDelivery {
    // An installed bridge and its off-window replacement can coexist.
    private var installed: Occurrence?
    private var created: Occurrence?

    func install(_ lifecycleID: UUID) {
        if installed?.id != lifecycleID { installed = Occurrence(id: lifecycleID) }
        else { installed?.cancelTeardown() }
        if created?.id == lifecycleID { created?.cancelTeardown() }
    }

    @discardableResult
    func deliver(
        _ event: ViewLifecycleBridge.Event,
        for view: ViewLifecycleBridge.LifecycleView,
        handler: @escaping @MainActor (ViewLifecycleBridge.LifecycleView?, UUID, ViewLifecycleBridge.Event) -> Void
    ) -> Task<Void, Never>? {
        let lifecycleID = view.id

        switch event {
        case .created:
            created = Occurrence(id: lifecycleID)
            handler(view, lifecycleID, event)
            return nil

        case .installedInWindow, .updated(isInstalledInWindow: true):
            install(lifecycleID)
            handler(view, lifecycleID, event)
            return nil

        case .updated(isInstalledInWindow: false):
            handler(view, lifecycleID, event)
            return nil

        case .dismantled, .deinitialized:
            if installed?.id == lifecycleID {
                return schedule(for: lifecycleID) { handler(nil, lifecycleID, event) }
            }
            guard let created, created.id == lifecycleID else { return nil }
            return created.scheduleTeardown { [self] in
                self.created = nil
                handler(nil, lifecycleID, event)
            }
        }
    }

    @discardableResult
    func schedule(
        for lifecycleID: UUID,
        _ action: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>? {
        guard let installed, installed.id == lifecycleID else { return nil }
        return installed.scheduleTeardown { [self] in
            self.installed = nil
            if created?.id == lifecycleID { created = nil }
            action()
        }
    }

    /// Keeps a bridge identity and its cancellable callback together.
    private final class Occurrence {
        let id: UUID
        private var teardown: Task<Void, Never>?

        init(id: UUID) { self.id = id }

        func cancelTeardown() {
            teardown?.cancel()
            teardown = nil
        }

        func scheduleTeardown(_ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
            cancelTeardown()
            // Leave the synchronous representable callback before mutating observed routing state.
            // A discarded occurrence cancels its work without being retained by the task.
            let task = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                teardown = nil
                action()
            }
            teardown = task
            return task
        }

        isolated deinit { teardown?.cancel() }
    }
}

struct ViewLifecycleBridge {
    enum Event {
        case created
        case updated(isInstalledInWindow: Bool)
        case installedInWindow(isInitial: Bool)
        case dismantled
        case deinitialized
    }

    let onEvent: @MainActor (LifecycleView, Event) -> Void

    init(onIdentifiedEvent: @escaping @MainActor (LifecycleView, Event) -> Void) {
        self.onEvent = onIdentifiedEvent
    }

    fileprivate func makeView() -> LifecycleView {
        let view = LifecycleView(onIdentifiedEvent: onEvent)
        onEvent(view, .created)
        return view
    }

    fileprivate func updateView(_ view: LifecycleView) {
        view.onEvent = onEvent
        view.onEvent(view, .updated(isInstalledInWindow: view.window != nil))
    }
}

#if canImport(UIKit)
extension ViewLifecycleBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> LifecycleView { makeView() }
    func updateUIView(_ uiView: LifecycleView, context: Context) { updateView(uiView) }
    static func dismantleUIView(_ uiView: LifecycleView, coordinator: ()) { uiView.notifyDismantled() }
}

#else
extension ViewLifecycleBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> LifecycleView { makeView() }
    func updateNSView(_ nsView: LifecycleView, context: Context) { updateView(nsView) }
    static func dismantleNSView(_ nsView: LifecycleView, coordinator: ()) { nsView.notifyDismantled() }
}
#endif

extension ViewLifecycleBridge {
    final class LifecycleView: PlatformView {
        let id = UUID()
        var onEvent: @MainActor (LifecycleView, Event) -> Void
        private var hasInstalledInWindow = false
        private var hasDismantled = false

        init(onIdentifiedEvent: @escaping @MainActor (LifecycleView, Event) -> Void) {
            self.onEvent = onIdentifiedEvent
            super.init(frame: .zero)
            #if canImport(UIKit)
            isUserInteractionEnabled = false
            #endif
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        #if canImport(UIKit)
        override func didMoveToWindow() {
            super.didMoveToWindow()
            handleMoveToWindow()
        }
        #else
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            handleMoveToWindow()
        }
        #endif

        private func handleMoveToWindow() {
            guard window != nil else {
                if hasInstalledInWindow {
                    onEvent(self, .updated(isInstalledInWindow: false))
                }
                return
            }

            let isInitial = hasInstalledInWindow == false
            hasInstalledInWindow = true
            onEvent(self, .installedInWindow(isInitial: isInitial))
        }

        func notifyDismantled() {
            guard hasDismantled == false else {
                return
            }

            hasDismantled = true
            onEvent(self, .dismantled)
        }

        func notifyDeinitialized() {
            onEvent(self, .deinitialized)
        }

        isolated deinit {
            notifyDeinitialized()
        }
    }
}
