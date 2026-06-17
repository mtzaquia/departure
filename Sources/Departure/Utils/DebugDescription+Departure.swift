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

extension AnyHashable {
    var departureDebugDescription: String {
        switch base {
        case let objectIdentifier as ObjectIdentifier:
            objectIdentifier.departureDebugDescription
        case let uuid as UUID:
            uuid.uuidString.split(separator: "-").first.map(String.init) ?? uuid.uuidString
        default:
            String(describing: base)
        }
    }
}

extension ObjectIdentifier {
    var departureDebugDescription: String {
        String(describing: self)
            .replacingOccurrences(of: "ObjectIdentifier(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .drop { $0 == "0" }
            .description
    }
}

extension Action {
    var departureDebugDescription: String {
        "\(departureDebugName(for: type(of: self)))#\(id.departureDebugDescription)"
    }
}

extension Route {
    var departureDebugDescription: String {
        "\(departureDebugName(for: type(of: self)))#\(id.departureDebugDescription)"
    }
}

extension AnyRouteDeclaration {
    var departureDebugDescription: String {
        let presentationDescription: String

        switch kind {
        case .push:
            presentationDescription = "push"
        case let .sheet(priority, _):
            presentationDescription = "sheet@\(priority)"
        case let .cover(priority, transition, _):
            presentationDescription = "cover.\(transition)@\(priority)"
        }

        let drivesPresentationDescription = drivesPresentation ? "" : ", discovery"
        return "\(departureDebugName(for: routeType))[\(presentationDescription)\(drivesPresentationDescription)]"
    }
}

private func departureDebugName(for type: Any.Type) -> String {
    String(reflecting: type).split(separator: ".").last.map(String.init) ?? String(describing: type)
}

extension RouteScope {
    var departureDebugDescription: String {
        if let route {
            return "routeScope#\(id.departureDebugDescription)(\(route.departureDebugDescription))"
        }

        if debugKind == .branch {
            return "branchScope#\(id.departureDebugDescription)"
        }

        let branchDescription = isFlatScope ? "" : ", active=\(activeBranch.departureDebugDescription)"
        return "rootScope#\(id.departureDebugDescription)\(branchDescription)"
    }

    var branchDebugDescription: String? {
        guard isFlatScope == false else {
            return nil
        }

        return "[\(branches.map { $0.id.departureDebugDescription }.joined(separator: ", "))]"
    }

    private var isFlatScope: Bool {
        branches.count == 1 && branches.first?.id == activeBranch
    }
}
#endif
