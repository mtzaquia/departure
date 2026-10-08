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

/// Definitions for a named child scope.
public struct Branch<Selection: Hashable & Sendable>: Sendable {
    let selection: Selection
    let declarations: [RouteScopeDeclaration]
    public init(_ selection: Selection, @RouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration]) {
        self.selection = selection
        self.declarations = declarations()
    }
    var routeScopeDeclarations: [RouteScopeDeclaration] { [.init(branch: selection, children: declarations)] }
}

/// Branches have independent paths and share the enclosing modal lane.
public struct Branches: Sendable {
    let declarations: [RouteScopeDeclaration]
    public init(concurrent: Bool = false, @RouteDeclarationBuilder _ declarations: () -> [RouteScopeDeclaration]) {
        self.declarations = declarations().map { declaration in
            precondition(declaration.branch != nil, "Branches accepts Branch declarations.")
            return .init(branch: declaration.branch!, children: declaration.children, concurrent: concurrent)
        }
    }
}
