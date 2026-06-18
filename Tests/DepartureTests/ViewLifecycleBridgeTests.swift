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
    @Test func transientWindowRemovalDoesNotEmitLifecycleEvents() {
        var events: [ViewLifecycleBridge.Event] = []
        let view = ViewLifecycleBridge.LifecycleView { event in
            events.append(event)
        }
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
        let view = ViewLifecycleBridge.LifecycleView { event in
            events.append(event)
        }
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
        let view = ViewLifecycleBridge.LifecycleView { event in
            events.append(event)
        }

        ViewLifecycleBridge.dismantleNSView(view, coordinator: ())
        ViewLifecycleBridge.dismantleNSView(view, coordinator: ())

        #expect(events.dismantledCount == 1)
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
