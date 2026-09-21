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

/// One modifier's registration, bound to the exact scope that accepted it.
/// A missing presentation anchor leaves the registration pending; installing the
/// anchor retries it without relying on SwiftUI to update the child again.
@MainActor
final class RouteScopeAttachment {
    enum Kind: String {
        case routes = ".routes"
        case hooks = ".hooks"
        case branch = ".routeBranch"
    }

    let id = AnyHashable(UUID())
    private let kind: Kind
    private weak var view: PlatformView?
    private var target: RouteScope?
    private var key: AnyHashable?
    private var installed: RouteScope?
    private var apply: ((RouteScope) -> Void)?
    private var remove: ((RouteScope) -> Void)?
    private var warnedScopes = Set<ObjectIdentifier>()

    init(kind: Kind) {
        self.kind = kind
    }

    func update(
        target: RouteScope?,
        key: AnyHashable? = nil,
        view: PlatformView?,
        apply: @escaping (RouteScope) -> Void,
        remove: @escaping (RouteScope) -> Void
    ) {
        let currentView = view ?? self.view
        if self.target !== target || self.key != key {
            detach()
            self.target = target
            self.key = key
            target?.ledger.observe(self)
        }

        self.view = currentView
        self.apply = apply
        self.remove = remove
        reconcile()
    }

    func detach() {
        if let installed {
            remove?(installed)
        }
        installed = nil
        target?.ledger.stopObserving(self)
        target = nil
        key = nil
        view = nil
        apply = nil
        remove = nil
    }

    func reconcile() {
        guard let target, let view else {
            return
        }

        switch target.ledger.ownership(of: view) {
        case .pending:
            // An anchor can disappear during a transient bridge replacement.
            // Retain an existing registration until the attachment itself ends.
            break

        case .managed:
            installed = target
            apply?(target)

        case .unmanaged:
            if let installed {
                remove?(installed)
                self.installed = nil
            }
            let scopeID = ObjectIdentifier(target)
            if warnedScopes.insert(scopeID).inserted {
                log.departureWarning(
                    "Ignoring `\(kind.rawValue)` attached outside a Departure-managed view for route scope "
                        + "`\(target.departureDebugDescription)`."
                )
            }
        }
    }
}
