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
    func onLifecycleEvent(_ handler: @escaping @MainActor (ViewLifecycleBridge.Event) -> Void) -> some View {
        modifier(ViewLifecycleEventModifier(handler: handler))
    }
}

private struct ViewLifecycleEventModifier: ViewModifier {
    let handler: @MainActor (ViewLifecycleBridge.Event) -> Void

    @State private var teardownDelivery = ViewLifecycleTeardownDelivery()

    func body(content: Content) -> some View {
        content.background {
            ViewLifecycleBridge(onIdentifiedEvent: { lifecycleView, event in
                let lifecycleID = lifecycleView.id

                switch event {
                case .installedInWindow, .updated(isInstalledInWindow: true):
                    teardownDelivery.install(lifecycleID)
                    handler(event)

                case .updated(isInstalledInWindow: false):
                    handler(event)

                case .dismantled, .deinitialized:
                    teardownDelivery.schedule(for: lifecycleID) {
                        handler(event)
                    }
                }
            })
            .frame(width: 0, height: 0)
        }
    }
}

/// Moves teardown work out of SwiftUI's representable dismantle stack. A later installation
/// invalidates pending work so transient bridge replacement cannot uninstall a live source.
final class ViewLifecycleTeardownDelivery {
    private var installedLifecycleID: UUID?
    private var generation = 0

    func install(_ lifecycleID: UUID) {
        installedLifecycleID = lifecycleID
        generation &+= 1
    }

    @discardableResult
    func schedule(
        for lifecycleID: UUID,
        _ action: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        generation &+= 1
        let scheduledGeneration = generation

        return Task { @MainActor [self] in
            await Task.yield()

            guard
                generation == scheduledGeneration,
                installedLifecycleID == lifecycleID
            else {
                return
            }

            installedLifecycleID = nil
            action()
        }
    }
}

struct ViewLifecycleBridge {
    enum Event {
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
        LifecycleView(onIdentifiedEvent: onEvent)
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
        private var hasDeinitialized = false

        init(onEvent: @escaping @MainActor (Event) -> Void) {
            self.onEvent = { _, event in
                onEvent(event)
            }
            super.init(frame: .zero)
            #if canImport(UIKit)
            isUserInteractionEnabled = false
            #endif
        }

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
            guard hasDeinitialized == false else {
                return
            }

            hasDeinitialized = true
            onEvent(self, .deinitialized)
        }

        isolated deinit {
            notifyDeinitialized()
        }
    }
}
