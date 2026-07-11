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

struct ScopeDeclarations {
    private var routesByType = OrderedStorage<ObjectIdentifier, AnyRouteDeclaration>()
    private var actionInterceptorsByType = OrderedStorage<ObjectIdentifier, AnyHookDeclaration>()
    private var unwindHandlersByRouteType = OrderedStorage<ObjectIdentifier, AnyHookDeclaration>()

    var routeAttachments: [AnyRouteDeclaration] {
        Array(routesByType.values)
    }

    var hookAttachments: [AnyHookDeclaration] {
        Array(actionInterceptorsByType.values)
        + Array(unwindHandlersByRouteType.values)
    }

    var hookIdentities: Set<HookDeclarationIdentity> {
        Set(hookAttachments.map(\.identity))
    }

    mutating func appendRoute(_ route: AnyRouteDeclaration) -> Bool {
        let key = ObjectIdentifier(route.routeType)
        guard routesByType[key] == nil else {
            return false
        }

        routesByType[key] = route
        return true
    }

    func routeAttachment(for routeType: any Route.Type) -> AnyRouteDeclaration? {
        routesByType[ObjectIdentifier(routeType)]
    }

    mutating func appendHook(_ hook: AnyHookDeclaration) -> Bool {
        switch hook.kind {
        case let .actionInterceptor(actionType, _):
            let key = ObjectIdentifier(actionType)
            guard actionInterceptorsByType[key] == nil else {
                return false
            }

            actionInterceptorsByType[key] = hook
            return true

        case let .unwindHandler(routeType, _):
            let key = ObjectIdentifier(routeType)
            guard unwindHandlersByRouteType[key] == nil else {
                return false
            }

            unwindHandlersByRouteType[key] = hook
            return true
        }
    }

    mutating func setHooks(_ hooks: [AnyHookDeclaration]) {
        removeHooks()
        for hook in hooks {
            _ = appendHook(hook)
        }
    }

    mutating func removeHooks() {
        actionInterceptorsByType.removeAll(keepingCapacity: true)
        unwindHandlersByRouteType.removeAll(keepingCapacity: true)
    }
}

struct DeclarationStore {
    var local = ScopeDeclarations()

    private var branches = OrderedStorage<AnyHashable, ScopeDeclarations>()

    init(branchIDs: [AnyHashable] = []) {
        for branchID in branchIDs where branches[branchID] == nil {
            branches[branchID] = ScopeDeclarations()
        }
    }

    var branchIDs: [AnyHashable] {
        Array(branches.keys)
    }

    var allHookAttachments: [AnyHookDeclaration] {
        local.hookAttachments + branches.values.flatMap(\.hookAttachments)
    }

    func declarations(forBranch branchID: AnyHashable) -> ScopeDeclarations {
        branches[branchID] ?? ScopeDeclarations()
    }

    mutating func appendRoute(_ route: AnyRouteDeclaration, toBranch branchID: AnyHashable) -> Bool {
        guard var declarations = branches[branchID] else {
            assertionFailure("Attempted to append a route to an undeclared branch.")
            return false
        }

        let inserted = declarations.appendRoute(route)
        branches[branchID] = declarations
        return inserted
    }

    mutating func setHooks(_ hooks: [AnyHookDeclaration], forBranch branchID: AnyHashable) {
        var declarations = branches[branchID] ?? ScopeDeclarations()
        declarations.setHooks(hooks)
        branches[branchID] = declarations
    }

    mutating func removeHooks(forBranch branchID: AnyHashable) {
        guard var declarations = branches[branchID] else {
            return
        }

        declarations.removeHooks()
        branches[branchID] = declarations
    }
}
