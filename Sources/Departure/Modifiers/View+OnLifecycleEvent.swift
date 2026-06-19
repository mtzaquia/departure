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

#if canImport(UIKit)
import UIKit
typealias PlatformView = UIView
#else
import AppKit
typealias PlatformView = NSView
#endif

extension View {
    func onLifecycleEvent(_ handler: @escaping @MainActor (ViewLifecycleBridge.Event) -> Void) -> some View {
        background {
            ViewLifecycleBridge(onEvent: handler)
                .frame(width: 0, height: 0)
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

    let onEvent: @MainActor (Event) -> Void

    fileprivate func makeView() -> LifecycleView {
        LifecycleView(onEvent: onEvent)
    }

    fileprivate func updateView(_ view: LifecycleView) {
        view.onEvent = onEvent
        view.onEvent(.updated(isInstalledInWindow: view.window != nil))
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
        var onEvent: @MainActor (Event) -> Void
        private var hasInstalledInWindow = false
        private var hasDismantled = false
        private var hasDeinitialized = false

        init(onEvent: @escaping @MainActor (Event) -> Void) {
            self.onEvent = onEvent
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
                    onEvent(.updated(isInstalledInWindow: false))
                }
                return
            }

            let isInitial = hasInstalledInWindow == false
            hasInstalledInWindow = true
            onEvent(.installedInWindow(isInitial: isInitial))
        }

        func notifyDismantled() {
            guard hasDismantled == false else {
                return
            }

            hasDismantled = true
            onEvent(.dismantled)
        }

        func notifyDeinitialized() {
            guard hasDeinitialized == false else {
                return
            }

            hasDeinitialized = true
            onEvent(.deinitialized)
        }

        isolated deinit {
            notifyDeinitialized()
        }
    }
}
