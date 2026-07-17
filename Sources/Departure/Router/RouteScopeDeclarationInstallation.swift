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

import SwiftUI

final class RouteScopeDeclarationInstallation {
    let initialID: AnyHashable
    private(set) var id: AnyHashable
    let sourceEnvironment = RouteSourceEnvironment()

    private var routeSourceID: AnyHashable?
    private var hookSourceID: AnyHashable?

    init(initialID: AnyHashable) {
        self.initialID = initialID
        self.id = initialID
    }

    func hasRouteSource(_ sourceID: AnyHashable) -> Bool {
        routeSourceID == sourceID
    }

    func installRouteSource(
        sourceID: AnyHashable,
        id: AnyHashable?,
        sourceEnvironment: EnvironmentValues
    ) {
        routeSourceID = sourceID
        updateSourceEnvironment(sourceEnvironment)

        if let id {
            self.id = id
        }
    }

    func uninstallRouteSource(sourceID: AnyHashable) -> Bool {
        guard routeSourceID == sourceID else {
            return false
        }

        routeSourceID = nil
        id = initialID
        updateSourceEnvironment(EnvironmentValues())
        return true
    }

    func installHookSource(sourceID: AnyHashable) {
        hookSourceID = sourceID
    }

    func uninstallHookSource(sourceID: AnyHashable) -> Bool {
        guard hookSourceID == sourceID else {
            return false
        }

        hookSourceID = nil
        return true
    }

    func updateSourceEnvironment(_ sourceEnvironment: EnvironmentValues) {
        self.sourceEnvironment.update(sourceEnvironment)
    }
}

final class RouteSourceEnvironment {
    private(set) var values = EnvironmentValues()

    func update(_ values: EnvironmentValues) {
        self.values = values
    }
}
