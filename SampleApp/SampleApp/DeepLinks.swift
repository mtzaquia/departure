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

import Departure
import Foundation

protocol SampleDeepLinkRoute: Route {}

extension SampleDeepLinkRoute {
    init?(url: URL) {
        guard let route = SampleDeepLink(url: url)?.route as? Self else {
            return nil
        }

        self = route
    }
}

struct SampleDeepLink {
    static let scheme = "departure-sample"
    static let host = "route"

    static let catalogue = [
        "landing",
        "start-info",
        "login",
        "login-replacement",
        "login-detail",
        "login-notice",
        "profile",
        "authentication-settings",
        "top-level-sheet",
        "top-level-cover",
        "top-level-replacement-cover",
        "high-priority-passthrough-sheet",
        "high-priority-blocking-sheet",
        "pending-priority",
        "navigation-bar-fade-occlusion",
        "appearance-settings",
        "alert",
        "critical",
        "critical-replacement",
        "message",
        "dismiss-probe",
        "nested-modal",
        "settings-modal",
        "reroute-chain-start",
        "reroute-chain-intermediate",
        "reroute-chain-final",
        "dropped",
        "undeclared",
    ]

    let path: String
    let route: any Route

    init?(url: URL) {
        guard
            url.scheme == Self.scheme,
            url.host == Self.host,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard
            pathComponents.count == 1,
            let path = pathComponents.first,
            Self.catalogue.contains(path),
            let route = Self.makeRoute(path: path, components: components)
        else {
            return nil
        }

        self.path = path
        self.route = route
    }

    private static func makeRoute(
        path: String,
        components: URLComponents
    ) -> (any Route)? {
        switch path {
        case "landing":
            LandingRoute()
        case "start-info":
            StartInfoRoute()
        case "login":
            loginRoute(from: components)
        case "login-replacement":
            LoginReplacementRoute()
        case "login-detail":
            LoginDetailRoute()
        case "login-notice":
            LoginNoticeRoute()
        case "profile":
            ProfileRoute()
        case "authentication-settings":
            authenticationSettingsRoute(from: components)
        case "top-level-sheet":
            TopLevelSheetRoute()
        case "top-level-cover":
            TopLevelCoverRoute()
        case "top-level-replacement-cover":
            TopLevelReplacementCoverRoute()
        case "high-priority-passthrough-sheet":
            HighPriorityPassthroughSheetRoute()
        case "high-priority-blocking-sheet":
            HighPriorityBlockingSheetRoute()
        case "pending-priority":
            PendingPriorityRoute()
        case "navigation-bar-fade-occlusion":
            NavigationBarFadeOcclusionRoute()
        case "appearance-settings":
            appearanceSettingsRoute(from: components)
        case "alert":
            AlertRoute()
        case "critical":
            CriticalRoute()
        case "critical-replacement":
            CriticalReplacementRoute()
        case "message":
            MessageRoute()
        case "dismiss-probe":
            DismissProbeRoute()
        case "nested-modal":
            NestedModalRoute()
        case "settings-modal":
            SettingsModalRoute()
        case "reroute-chain-start":
            RerouteChainStartRoute()
        case "reroute-chain-intermediate":
            RerouteChainIntermediateRoute()
        case "reroute-chain-final":
            RerouteChainFinalRoute()
        case "dropped":
            DroppedRoute()
        case "undeclared":
            UndeclaredRoute()
        default:
            nil
        }
    }

    private static func loginRoute(from components: URLComponents) -> LoginRoute? {
        guard let nextPath = components.queryValue(named: "next") else {
            return LoginRoute(nextRoute: nil)
        }

        guard
            catalogue.contains(nextPath),
            let nextRoute = makeRoute(path: nextPath, components: URLComponents())
        else {
            return nil
        }

        return LoginRoute(nextRoute: nextRoute)
    }

    private static func authenticationSettingsRoute(
        from components: URLComponents
    ) -> AuthenticationSettingsRoute? {
        let state = AuthenticationSettingsRouteState()

        guard let value = components.queryValue(named: "local-route") else {
            return AuthenticationSettingsRoute(state: state)
        }

        switch value {
        case "true", "1":
            state.attachesLocalRoute = true
        case "false", "0":
            state.attachesLocalRoute = false
        default:
            return nil
        }

        return AuthenticationSettingsRoute(state: state)
    }

    private static func appearanceSettingsRoute(
        from components: URLComponents
    ) -> AppearanceSettingsRoute? {
        guard let value = components.queryValue(named: "value") else {
            return AppearanceSettingsRoute(value: nil)
        }

        guard let uuid = UUID(uuidString: value) else {
            return nil
        }

        return AppearanceSettingsRoute(value: uuid)
    }
}

private extension URLComponents {
    func queryValue(named name: String) -> String? {
        queryItems?.first { $0.name == name }?.value
    }
}
