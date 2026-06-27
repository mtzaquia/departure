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

extension Router {
    enum RouteContext {
        case normal(path: RoutePath)
        case high(
            path: RoutePath,
            startIndex: [RouteScope].Index,
            presentationScope: RouteScope
        )
        case critical(
            path: RoutePath,
            startIndex: [RouteScope].Index,
            presentationScope: RouteScope
        )

        var path: RoutePath {
            switch self {
            case .normal(let path), .high(let path, _, _), .critical(let path, _, _):
                path
            }
        }

        var priority: RoutePriority {
            switch self {
            case .normal: .normal
            case .high: .high
            case .critical: .critical
            }
        }

        var elevatedStartIndex: [RouteScope].Index? {
            switch self {
            case .normal:
                return nil

            case .high(_, let startIndex, _), .critical(_, let startIndex, _):
                return startIndex
            }
        }

        var elevatedRouteScope: RouteScope? {
            switch self {
            case .normal:
                return nil

            case .high(let path, let startIndex, _), .critical(let path, let startIndex, _):
                guard path.scopes.indices.contains(startIndex) else {
                    return nil
                }

                return path.scopes[startIndex]
            }
        }

        var elevatedBasePathIndex: [RouteScope].Index? {
            switch self {
            case .normal:
                return nil

            case .high(let path, let startIndex, _), .critical(let path, let startIndex, _):
                guard startIndex > path.scopes.startIndex else {
                    return nil
                }

                return path.scopes.index(before: startIndex)
            }
        }

        var elevatedPresentationScope: RouteScope? {
            switch self {
            case .normal:
                return nil

            case .high(_, _, let presentationScope), .critical(_, _, let presentationScope):
                return presentationScope
            }
        }

        func contains(path: RoutePath, pathIndex: [RouteScope].Index?) -> Bool {
            switch self {
            case .normal:
                return false

            case .high(let contextPath, let startIndex, _), .critical(let contextPath, let startIndex, _):
                guard path === contextPath, let pathIndex else {
                    return false
                }

                return pathIndex >= startIndex
            }
        }
    }

    var currentRoutePath: RoutePath {
        activeContext.path
    }

    var activeContext: RouteContext {
        criticalContext ?? highContext ?? normalContext
    }

    var highestElevatedContext: RouteContext? {
        criticalContext ?? highContext
    }

    func elevatedContext(for priority: RoutePriority) -> RouteContext? {
        switch priority {
        case .normal:
            return nil

        case .high:
            return highContext

        case .critical:
            return criticalContext
        }
    }

    func setElevatedContext(_ context: RouteContext?, for priority: RoutePriority) {
        mutateRouteGraph {
            switch priority {
            case .normal:
                return

            case .high:
                highContext = context

            case .critical:
                criticalContext = context
            }
        }
    }

    func elevatedContext(containing match: DeclarationMatch) -> RouteContext? {
        elevatedContexts(containingPath: match.path, pathIndex: match.pathIndex).first
    }

    func elevatedContext(
        containingPath path: RoutePath,
        pathIndex: [RouteScope].Index?,
        minimumPriority: RoutePriority
    ) -> RouteContext? {
        elevatedContexts(containingPath: path, pathIndex: pathIndex).first {
            $0.priority >= minimumPriority
        }
    }

    func elevatedContexts(containingPath path: RoutePath, pathIndex: [RouteScope].Index?) -> [RouteContext] {
        elevatedContexts.filter {
            $0.contains(path: path, pathIndex: pathIndex)
        }
    }

    var elevatedContexts: [RouteContext] {
        [criticalContext, highContext].compactMap { $0 }
    }

    func clearElevatedContexts() {
        mutateRouteGraph {
            highContext = nil
            criticalContext = nil
        }
    }

    var normalContext: RouteContext {
        .normal(path: currentNormalRoutePath)
    }

    var currentNormalRoutePath: RoutePath {
        if let activeTopLevelPath = rootPath.last?.activeLocalScope.owningPath {
            return activeTopLevelPath
        }

        if let activeRootPath = root.activeLocalScope.owningPath {
            return activeRootPath
        }

        return rootPath
    }
}
