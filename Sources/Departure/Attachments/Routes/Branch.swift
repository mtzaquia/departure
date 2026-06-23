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

/// Groups declarations under a branch selection value.
///
/// Use ``Branch`` inside ``SwiftUICore/View/routes(id:branch:_:)`` so routes are discoverable even when
/// a branch view has not been built yet.
///
/// ```swift
/// TabView(selection: $tab) {
///     HomeView()
///         .routeBranch(AppTab.home)
/// }
/// .routes(branch: $tab) {
///     Branch(AppTab.home) {
///         Push(DetailRoute.self)
///     }
/// }
/// ```
///
/// - Important: Declarations inside ``Branch`` are discovery-only until a matching
///   ``SwiftUICore/View/routeBranch(_:)`` adopts them.
public struct Branch<Selection: Hashable>: Sendable where Selection: Sendable {
    let selection: Selection
    let declarations: [RouteScopeDeclaration]

    /// Creates a branch declaration group.
    public init(
        _ selection: Selection,
        @RouteDeclarationBuilder declarations: () -> [RouteScopeDeclaration]
    ) {
        self.selection = selection
        self.declarations = declarations()
    }

    var routeScopeDeclarations: [RouteScopeDeclaration] {
        declarations.map { declaration in
            RouteScopeDeclaration(
                branch: selection,
                routes: declaration.routes.drivingPresentation(false)
            )
        }
    }
}
