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

@Observable
final class RouteLane {
    @ObservationIgnored private weak var owner: RouteScope?
    @ObservationIgnored private weak var occupant: RouteScope?

    var modal: RouteScope? {
        access(keyPath: \.modal)
        guard let occupant, let space = owner?.space, occupant.belongs(to: space) else { return nil }
        return occupant
    }

    init(owner: RouteScope) { self.owner = owner }
    var depth: Int {
        guard let owner, owner.anchorSpace == nil, owner.presentationDeclaration?.presentationKind.isModal == true else { return 0 }
        return (owner.previousRouteScope?.lane.depth ?? 0) + 1
    }

    var deepestModal: RouteScope? { modal?.lane.deepestModal ?? modal }

    func present(_ scope: RouteScope) {
        precondition(modal == nil, "A Y lane can own only one modal transition.")
        precondition(scope.previousRouteScope?.lane === self, "A modal advances from its presenting lane.")
        withMutation(keyPath: \.modal) { occupant = scope }
    }
}
