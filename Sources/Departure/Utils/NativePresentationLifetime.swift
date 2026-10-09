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

/// The native owner's one rendered occurrence. Desired navigation stays in the live tree;
/// this state retains outgoing content until the adapter acknowledges native completion.
@Observable
final class NativePresentationLifetime {
    private struct CompletedOccurrence { weak var scope: RouteScope? }
    private enum Phase {
        case idle(CompletedOccurrence)
        case preparing(RouteDestinationSnapshot)
        case showing(RouteDestinationSnapshot)
        case dismissing(RouteDestinationSnapshot)
    }
    private var phase: Phase = .idle(CompletedOccurrence())

    var presentation: RouteDestinationSnapshot? {
        switch phase {
        case .idle: nil
        case .preparing(let presentation), .showing(let presentation), .dismissing(let presentation): presentation
        }
    }
    var isPresented: Bool {
        switch phase {
        case .preparing, .showing: true
        case .idle, .dismissing: false
        }
    }
    var dismissalID: PresentedRoute.ID? { isPresented ? nil : presentation?.id }

    /// Never admits a successor while an older occurrence is still rendered.
    /// The coordinator owns pending navigation, so no pending route is stored here.
    func synchronize(_ route: PresentedRoute?, build: (PresentedRoute) -> RouteDestinationSnapshot) {
        switch phase {
        case .idle(let completed):
            guard let route, route.scope !== completed.scope else { return }
            phase = .preparing(build(route))
            route.scope.trackNativePresentation(self)
        case .preparing(let presentation), .showing(let presentation):
            if route?.id != presentation.id { beginDismissal(of: presentation.id) }
        case .dismissing: break
        }
    }

    /// SwiftUI has created the native destination, or UIKit has installed its owner.
    func didAdmitPresentation(of id: PresentedRoute.ID) {
        guard case .preparing(let presentation) = phase, presentation.id == id else { return }
        phase = .showing(presentation)
    }

    @discardableResult
    func beginDismissal(of id: PresentedRoute.ID) -> Bool {
        guard let presentation, presentation.id == id else { return false }
        switch phase {
        case .preparing:
            // SwiftUI may coalesce a request and its cancellation without presenting anything.
            // There will be no native onDismiss to wait for in that case.
            phase = .idle(CompletedOccurrence(scope: presentation.route.scope))
            presentation.route.scope.nativePresentationDidEnd()
            return true
        case .showing:
            phase = .dismissing(presentation)
            return true
        case .idle, .dismissing: return false
        }
    }

    func requestDismissal(of id: PresentedRoute.ID, in router: RouterEngine) {
        guard let scope = presentation?.route.scope, beginDismissal(of: id),
              scope.isNativePresentationOwned(by: self) else { return }
        router.nativePresentationDidDismiss(scope)
    }

    /// Native callbacks carry the exiting identity; duplicate/stale callbacks are inert.
    func completeDismissal(of id: PresentedRoute.ID, in router: RouterEngine) {
        guard let presentation, presentation.id == id else { return }
        // Owner destruction may be the first native event. A requested dismissal
        // already started its unwind, even if its before-commit callback is pending.
        if isPresented, presentation.route.scope.isNativePresentationOwned(by: self) {
            router.nativePresentationDidDismiss(presentation.route.scope)
        }
        phase = .idle(CompletedOccurrence(scope: presentation.route.scope))
        presentation.route.scope.nativePresentationDidEnd()
    }
}
