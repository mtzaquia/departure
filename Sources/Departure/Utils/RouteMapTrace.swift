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

#if DEBUG
    import Foundation

    extension RouteDefinitions {
        var departureMapTrace: String {
            var tree = RouteMapTrace(destinations: traceDestinations)
            return tree.render(traceDeclarations)
        }
    }

    /// Formats definition metadata without constructing views or printing route/branch values.
    private struct RouteMapTrace {
        private struct Node {
            let label: String
            var children: [Node] = []
        }

        let destinations: RouteDestinationBindings
        private var destinationNumbers: [AnyRouteDestination: Int] = [:]

        init(destinations: RouteDestinationBindings) {
            self.destinations = destinations
        }

        mutating func render(_ declarations: [RouteScopeDeclaration]) -> String {
            let counts = routeCounts(declarations)
            var roots: [Node] = []
            for priority in [RoutePriority.default, .high, .critical] {
                let selected = declarations.compactMap { declaration -> RouteScopeDeclaration? in
                    if case .routes(let routes) = declaration.content {
                        let routes = routes.filter { $0.priority == priority }
                        return routes.isEmpty ? nil : .init(routes: routes)
                    }
                    return priority == .default ? declaration : nil
                }
                let children = nodes(selected, counts: counts)
                if !children.isEmpty { roots.append(Node(label: String(describing: priority), children: children)) }
            }
            return (["root"] + lines(roots)).joined(separator: "\n")
        }

        private mutating func nodes(_ declarations: [RouteScopeDeclaration], counts: [ObjectIdentifier: Int]? = nil) -> [Node] {
            let counts = counts ?? routeCounts(declarations)
            let branchGroups = declarations.filter {
                if case .branches = $0.content { return true }
                return false
            }.count
            var result: [Node] = []
            for declaration in declarations {
                switch declaration.content {
                case .routes(let routes):
                    for route in routes {
                        var label = "\(style(route.presentation.style)) \(departureDebugName(for: route.routeType)) → \(binding(route.routeType))"
                        if counts[ObjectIdentifier(route.routeType), default: 0] > 1 { label += " [declaration conflict]" }
                        result.append(Node(label: label, children: nodes(route.children)))
                    }
                case .branches(let concurrent, let children):
                    let selections = children.compactMap(\.branch)
                    var branches: [Node] = []
                    for (index, child) in children.enumerated() {
                        guard case .branch(let selection, let declarations) = child.content else { continue }
                        let name = departureDebugName(for: type(of: selection.base))
                        let duplicate = selections.filter { $0 == selection }.count > 1
                        let suffix = duplicate ? " [branch conflict]" : ""
                        branches.append(Node(label: "branch #\(index + 1) (\(name))\(suffix)", children: nodes(declarations)))
                    }
                    let suffix = branchGroups > 1 ? " [container conflict]" : ""
                    result.append(Node(label: "branches\(concurrent ? " (concurrent)" : "")\(suffix)", children: branches))
                case .scopeID, .destinations:
                    break
                case .branch:
                    result.append(Node(label: "[branch outside container]"))
                }
            }
            return result
        }

        private mutating func binding(_ route: any Route.Type) -> String {
            switch destinations.binding(for: route) {
            case .declared(let destination):
                let number = destinationNumbers[destination] ?? destinationNumbers.count + 1
                destinationNumbers[destination] = number
                return "destination #\(number)"
            case .conflict:
                return "[destination conflict]"
            case nil:
                return "[missing destination]"
            }
        }

        private func routeCounts(_ declarations: [RouteScopeDeclaration]) -> [ObjectIdentifier: Int] {
            declarations.flatMap(\.routes).reduce(into: [:]) { counts, route in
                counts[ObjectIdentifier(route.routeType), default: 0] += 1
            }
        }

        private func style(_ style: RoutePresentation.Style) -> String {
            switch style {
            case .push: "push"
            case .replace: "replace"
            case .sheet: "sheet"
            case .cover(let transition): "cover.\(transition)"
            }
        }

        private func lines(_ nodes: [Node], prefix: String = "") -> [String] {
            nodes.enumerated().flatMap { index, node in
                let last = index == nodes.count - 1
                return [prefix + (last ? "└─ " : "├─ ") + node.label]
                    + lines(node.children, prefix: prefix + (last ? "   " : "│  "))
            }
        }
    }
#endif
