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

import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Automatic boundaries wrap arbitrary content, which may create its own stack.
/// Keep their push slot absent until the boundary itself has a navigation ancestor.
@Observable
final class AutomaticPushHost {
    enum Placement { case pending, insideStack, outsideStack }
    private(set) var placement = Placement.pending
    @ObservationIgnored private var lifecycleID: UUID?
    @ObservationIgnored private var check: Task<Void, Never>?
    @ObservationIgnored private var transition: ObjectIdentifier?

    func handle(_ event: ViewLifecycleBridge.Event, id: UUID, view: PlatformView?) {
        switch event {
        case .created:
            if lifecycleID != id { check?.cancel(); check = nil; transition = nil }
            lifecycleID = id
        case .installedInWindow:
            if lifecycleID != id { check?.cancel(); check = nil; transition = nil }
            lifecycleID = id
            scheduleCheck(id: id, view: view)
        case .updated(isInstalledInWindow: true):
            guard lifecycleID == id else { return }
            scheduleCheck(id: id, view: view)
        case .updated(isInstalledInWindow: false):
            break // A transient window loss must not remove an active push slot.
        case .ended:
            guard lifecycleID == id else { return }
            check?.cancel()
            check = nil
            transition = nil
            lifecycleID = nil
        }
    }

    private func scheduleCheck(id: UUID, view: PlatformView?) {
        guard check == nil, let view else { return }
        // Leave the native installation callback. Stack-side explicit hosts can
        // bind before the automatic slot appears; no pending item is required.
        check = Task { @MainActor [weak self, weak view] in
            guard let self, !Task.isCancelled, lifecycleID == id else { return }
            check = nil
            guard let view, view.window != nil else { return }
            #if canImport(UIKit)
            // iOS 17 can lose a child requested from the pushed parent's .task
            // while its native push is still animating. Register the child's slot
            // after that transition, using completion rather than a timed delay.
            if #unavailable(iOS 18), let controller = Self.controller(containing: view),
               let coordinator = controller.transitionCoordinator, coordinator.isAnimated {
                let identity = ObjectIdentifier(coordinator as AnyObject)
                if transition == identity { return }
                transition = identity
                if coordinator.animate(alongsideTransition: nil, completion: { [weak self, weak view] _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, self.lifecycleID == id, self.transition == identity else { return }
                        self.transition = nil
                        self.scheduleCheck(id: id, view: view)
                    }
                }) { return }
                transition = nil
            }
            let next: Placement = Self.hasNavigationAncestor(view) ? .insideStack : .outsideStack
            #else
            // AppKit exposes no public navigation-controller containment API.
            let next: Placement = .insideStack
            #endif
            if placement != next { placement = next }
        }
    }

    #if canImport(UIKit)
    static func hasNavigationAncestor(_ view: UIView) -> Bool {
        guard let controller = controller(containing: view) else { return false }
        return controller is UINavigationController || controller.navigationController != nil
    }

    private static func controller(containing view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
    #endif

    isolated deinit { check?.cancel() }
}
