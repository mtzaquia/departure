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

        var path: RoutePath {
            switch self {
            case .normal(let path), .high(let path, _, _):
                path
            }
        }

        var highStartIndex: [RouteScope].Index? {
            guard case .high(_, let startIndex, _) = self else {
                return nil
            }

            return startIndex
        }

        var highRouteScope: RouteScope? {
            guard
                case .high(let path, let startIndex, _) = self,
                path.scopes.indices.contains(startIndex)
            else {
                return nil
            }

            return path.scopes[startIndex]
        }

        var highBasePathIndex: [RouteScope].Index? {
            guard
                case .high(let path, let startIndex, _) = self,
                startIndex > path.scopes.startIndex
            else {
                return nil
            }

            return path.scopes.index(before: startIndex)
        }

        var highPresentationScope: RouteScope? {
            guard case .high(_, _, let presentationScope) = self else {
                return nil
            }

            return presentationScope
        }

        func contains(_ match: DeclarationMatch) -> Bool {
            contains(path: match.path, pathIndex: match.pathIndex)
        }

        func contains(path: RoutePath, pathIndex: [RouteScope].Index?) -> Bool {
            guard
                case .high(let contextPath, let startIndex, _) = self,
                path === contextPath,
                let pathIndex
            else {
                return false
            }

            return pathIndex >= startIndex
        }
    }

    var currentRoutePath: RoutePath {
        activeContext.path
    }

    var activeContext: RouteContext {
        highContext ?? normalContext
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
