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
import Testing
@testable import Departure

#if DEBUG
@MainActor @Suite struct RouteAppendLoggingTests {
    @Test(arguments: [RoutePresentation.Style.sheet, .cover(.slide), .cover(.fade)], [false, true])
    func modalPushExplainsItsSelectedHostAndConditionalFix(ownerStyle: RoutePresentation.Style, explicit: Bool) async throws {
        let (engine, owner, match) = try await context(ownerStyle: ownerStyle)
        owner.bindRoutingHost(RoutePresentationHostID(), automatic: true, environment: owner.sourceEnvironment)
        if explicit {
            owner.bindRoutingHost(RoutePresentationHostID(), automatic: false, environment: owner.sourceEnvironment)
        }
        let route = HomeDetailRoute()
        await Router(engine: engine, scope: owner).present(route)
        let appended = try #require(engine.defaultSpace.rootPath.last)
        #expect(appended.route is HomeDetailRoute)
        #expect(!appended.isInstalledInView)

        let path = engine.defaultSpace.rootPath.departureDebugPathDescription
        let event = DepartureLogEvent.routeAppended(route: route, path: path, match: match)
        let host = explicit ? "explicit" : "automatic"
        var expected = "[route][r:12345678] ✓ appended \(route.departureDebugDescription) to path"
            + " | style=push owner=SettingsRoute host=\(host)\n  path: \(path)"
        if !explicit {
            expected += "\n  hint: SettingsRoute has no explicit routing host."
                + " If its RouteDestination creates a NavigationStack, add `.routing()`"
                + " to the root content inside that stack."
        }
        let rendered = DepartureLogTrace.$id.withValue("r:12345678") { event.renderedMessage }
        #expect(event.logLevel == .normal)
        #expect(rendered == expected)
    }

    @Test(arguments: [RoutePresentation.Style.push, .replace])
    func automaticNonModalOwnersDoNotSuggestAMissingModalHost(ownerStyle: RoutePresentation.Style) async throws {
        let (_, owner, match) = try await context(ownerStyle: ownerStyle)
        owner.bindRoutingHost(RoutePresentationHostID(), automatic: true, environment: owner.sourceEnvironment)
        let message = DepartureLogEvent.routeAppended(route: HomeDetailRoute(), path: "path", match: match).message
        #expect(message.contains("style=push owner=SettingsRoute host=automatic"))
        #expect(!message.contains("hint:"))
    }

    @Test(arguments: [RoutePresentation.Style.sheet, .cover(.slide), .cover(.fade), .replace])
    func nonPushAppendsDoNotSuggestAMissingStack(childStyle: RoutePresentation.Style) async throws {
        let (_, owner, match) = try await context(ownerStyle: .sheet, childStyle: childStyle)
        owner.bindRoutingHost(RoutePresentationHostID(), automatic: true, environment: owner.sourceEnvironment)
        let message = DepartureLogEvent.routeAppended(route: HomeDetailRoute(), path: "path", match: match).message
        #expect(message.contains("owner=SettingsRoute host=automatic"))
        #expect(!message.contains("hint:"))
    }

    @Test func automaticRootPushDoesNotSuggestAMissingModalHost() throws {
        let engine = RouterEngine(routes: RootRouteMap { testPush(testDestination(HomeDetailRoute.self)) })
        engine.root.bindRoutingHost(RoutePresentationHostID(), automatic: true, environment: engine.root.sourceEnvironment)
        let match = try #require(engine.spaces.firstDeclaration(including: HomeDetailRoute.self)?.declaration)
        let event = DepartureLogEvent.routeAppended(route: HomeDetailRoute(), path: "path", match: match)
        #expect(event.message.contains("style=push owner=root host=automatic"))
        #expect(!event.message.contains("hint:"))
    }

    @Test func hostDiagnosticsFollowSelectionConflictsAndRemoval() async throws {
        let (_, owner, match) = try await context(ownerStyle: .sheet)
        let automatic = RoutePresentationHostID(), first = RoutePresentationHostID(), second = RoutePresentationHostID()
        let event = DepartureLogEvent.routeAppended(route: HomeDetailRoute(), path: "path", match: match)
        #expect(event.message.contains("host=missing"))
        #expect(!event.message.contains("hint:"))
        owner.bindRoutingHost(automatic, automatic: true, environment: owner.sourceEnvironment)
        #expect(event.message.contains("host=automatic"))
        #expect(event.message.contains("hint:"))
        owner.bindRoutingHost(first, automatic: false, environment: owner.sourceEnvironment)
        #expect(event.message.contains("host=explicit"))
        #expect(!event.message.contains("hint:"))
        owner.bindRoutingHost(second, automatic: false, environment: owner.sourceEnvironment)
        #expect(owner.presentationHostKind == .conflict)
        #expect(event.message.contains("host=conflict"))
        #expect(!event.message.contains("hint:"))
        owner.unbindRoutingHost(second)
        #expect(event.message.contains("host=explicit"))
        owner.unbindRoutingHost(first)
        #expect(event.message.contains("host=automatic"))
        #expect(event.message.contains("hint:"))
        owner.unbindRoutingHost(automatic)
        #expect(event.message.contains("host=missing"))
        #expect(!event.message.contains("hint:"))
    }

    private func context(ownerStyle: RoutePresentation.Style, childStyle: RoutePresentation.Style = .push) async throws
        -> (RouterEngine, RouteScope, RouterEngine.ResolvedRouteTarget) {
        let engine = RouterEngine(routes: RootRouteMap {
            AnyRouteDeclaration(SettingsRoute.self, presentation: .init(style: ownerStyle, priority: .default), children: [
                RouteScopeDeclaration(routes: [
                    AnyRouteDeclaration(HomeDetailRoute.self, presentation: .init(style: childStyle, priority: .default))
                ])
            ])
        } destinations: {
            testDestination(SettingsRoute.self)
            testDestination(HomeDetailRoute.self)
        })
        await engine.present(SettingsRoute())
        let owner = try #require(engine.defaultSpace.rootPath.last)
        let match = try #require(engine.spaces.firstDeclaration(including: HomeDetailRoute.self,
            origin: RouteRequestOrigin(scope: owner))?.declaration)
        return (engine, owner, match)
    }
}
#endif
