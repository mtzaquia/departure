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

extension View {
    func onLifecycleEvent(_ handler: @escaping @MainActor (ViewLifecycleBridge.Event) -> Void) -> some View {
        background {
            ViewLifecycleBridge(onEvent: handler)
                .frame(width: 0, height: 0)
        }
    }
}

#if canImport(UIKit)
import UIKit

struct ViewLifecycleBridge: UIViewRepresentable {
    enum Event {
        case installedInWindow(isInitial: Bool)
        case removedFromWindow
        case deinitialized
    }

    let onEvent: @MainActor (Event) -> Void

    func makeUIView(context: Context) -> LifecycleView {
        LifecycleView(onEvent: onEvent)
    }

    func updateUIView(_ uiView: LifecycleView, context: Context) {
        uiView.onEvent = onEvent
    }

    static func dismantleUIView(_ uiView: LifecycleView, coordinator: ()) {
        uiView.notifyDeinitialized()
    }

    final class LifecycleView: UIView {
        var onEvent: @MainActor (Event) -> Void
        private var hasInstalledInWindow = false
        private var hasDeinitialized = false

        init(onEvent: @escaping @MainActor (Event) -> Void) {
            self.onEvent = onEvent
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()

            guard window != nil else {
                if hasInstalledInWindow {
                    onEvent(.removedFromWindow)
                }
                return
            }

            let isInitial = hasInstalledInWindow == false
            hasInstalledInWindow = true
            onEvent(.installedInWindow(isInitial: isInitial))
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
#else
import AppKit

struct ViewLifecycleBridge: NSViewRepresentable {
    enum Event {
        case installedInWindow(isInitial: Bool)
        case removedFromWindow
        case deinitialized
    }

    let onEvent: @MainActor (Event) -> Void

    func makeNSView(context: Context) -> LifecycleView {
        LifecycleView(onEvent: onEvent)
    }

    func updateNSView(_ nsView: LifecycleView, context: Context) {
        nsView.onEvent = onEvent
    }

    static func dismantleNSView(_ nsView: LifecycleView, coordinator: ()) {
        nsView.notifyDeinitialized()
    }

    final class LifecycleView: NSView {
        var onEvent: @MainActor (Event) -> Void
        private var hasInstalledInWindow = false
        private var hasDeinitialized = false

        init(onEvent: @escaping @MainActor (Event) -> Void) {
            self.onEvent = onEvent
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard window != nil else {
                if hasInstalledInWindow {
                    onEvent(.removedFromWindow)
                }
                return
            }

            let isInitial = hasInstalledInWindow == false
            hasInstalledInWindow = true
            onEvent(.installedInWindow(isInitial: isInitial))
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
#endif
