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

/// Type-erased hook metadata.
public struct AnyHookDeclaration: Sendable {
    enum Kind: Sendable {
        case actionInterceptor(any Action.Type, AnyActionInterceptor)
        case unwindHandler(any Route.Type, AnyUnwindHandler)
    }

    let kind: Kind
}

/// A value accepted by ``SwiftUICore/View/hooks(_:)``.
public protocol HookDeclaration {
    var _hookDeclarations: [AnyHookDeclaration] { get }
}

// MARK: - Internal helpers

extension AnyHookDeclaration {
    var actionInterceptorType: (any Action.Type)? {
        switch kind {
        case let .actionInterceptor(actionType, _):
            actionType

        default:
            nil
        }
    }

    var unwindHandlerRouteType: (any Route.Type)? {
        switch kind {
        case let .unwindHandler(routeType, _):
            routeType

        default:
            nil
        }
    }

    func interceptor(for actionType: (some Action).Type) -> AnyActionInterceptor? {
        switch kind {
        case let .actionInterceptor(candidateActionType, actionInterceptor) where candidateActionType == actionType:
            return actionInterceptor

        default:
            return nil
        }
    }

    func unwindHandler(for routeType: any Route.Type) -> AnyUnwindHandler? {
        switch kind {
        case let .unwindHandler(candidateRouteType, unwindHandler) where candidateRouteType == routeType:
            return unwindHandler

        default:
            return nil
        }
    }
}
