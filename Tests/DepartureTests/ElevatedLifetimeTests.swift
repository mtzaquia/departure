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

@MainActor @Suite struct ElevatedLifetimeTests {
    @Test func removingDefaultDestinationKeepsRootPriorityPresentations() async throws {
        let (engine, defaultScope, _, _) = try await makeChain()
        #expect(!((await engine.unwindPrevious(from: defaultScope))))
        #expect(engine.defaultSpace.rootPath.last === defaultScope)
        #expect(engine.spaces.highSpace != nil)
        #expect(engine.spaces.criticalSpace != nil)
    }
    @Test func removingHighDestinationKeepsRootCriticalAndDefault() async throws {
        let (engine, defaultScope, _, _) = try await makeChain()
        #expect(await RootRouter(engine: engine).dismissSpace(.high))
        #expect(engine.defaultSpace.rootPath.last === defaultScope)
        #expect(engine.spaces.highSpace == nil)
        #expect(engine.spaces.criticalSpace != nil)
    }
    @Test func elevatedNativeTeardownClearsOnlyItsOwnPriority() async throws {
        let (engine, defaultScope, high, _) = try await makeChain()
        engine.routeScopeDidInstallInView(high)
        engine.routeScopeDidLeaveView(high)
        #expect(engine.defaultSpace.rootPath.last === defaultScope)
        #expect(engine.spaces.highSpace == nil)
        #expect(engine.spaces.criticalSpace != nil)
    }
    @Test func ownerRemovalClearsAllElevatedPriorities() async throws {
        let (engine, _, _, _) = try await makeChain()
        #expect(await RootRouter(engine: engine).dismissSpaces())
        #expect(engine.defaultSpace.rootPath.count == 1)
        #expect(engine.spaces.highSpace == nil)
        #expect(engine.spaces.criticalSpace == nil)
    }
    @Test func allElevatedOriginsAreRootAnchored() async throws {
        let (engine, _, _, _) = try await makeChain()
        #expect(engine.spaces.highSpace?.root.presentationOrigin === engine.root)
        #expect(engine.spaces.criticalSpace?.root.presentationOrigin === engine.root)
    }
    private func makeChain() async throws -> (RouterEngine, RouteScope, RouteScope, RouteScope) {
        let engine = RouterEngine(routes: RootRouteMap {
            Push(RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() })
        } highPriority: {
            Sheet(RouteDestination(LoginRoute.self) { _, _ in EmptyView() })
        } criticalPriority: {
            Sheet(RouteDestination(AlertRoute.self) { _, _ in EmptyView() })
        })
        await engine.present(HomeDetailRoute())
        let defaultScope = try #require(engine.defaultSpace.rootPath.last)
        await engine.present(LoginRoute())
        let high = try #require(engine.spaces.highSpace?.currentRouteScope)
        await engine.present(AlertRoute())
        let critical = try #require(engine.spaces.criticalSpace?.currentRouteScope)
        return (engine, defaultScope, high, critical)
    }
}
