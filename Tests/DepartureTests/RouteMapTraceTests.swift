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

import RouteDomainFixtures
import SwiftUI
import Testing

@testable import Departure

#if DEBUG
    @MainActor @Suite(.serialized) struct RouteMapTraceTests {
        @Test func adoptedTreeShowsStableDestinationMatchesWithoutBuildingViews() {
            var builds = 0
            let number = RouteDestination(NumberedRoute.self) { _, _ in
                builds += 1
                return EmptyView()
            }
            let feature = RouteMap {
                Push(NumberedRoute.self)
            } destinations: {
                number
            }
            let engine = RouterEngine(
                routes: RootRouteMap {
                    Sheet(DomainOnlyRoute.self)
                    Branches(concurrent: true) {
                        Branch("private-first") { feature }
                        Branch("private-second") { feature }
                    }
                    HighPriority {
                        Cover(HomeDetailRoute.self, transition: .fade) { Sheet(DomainOnlyRoute.self) }
                    }
                } destinations: {
                    RouteDestination(DomainOnlyRoute.self) { _, _ in
                        builds += 1
                        return EmptyView()
                    }
                    RouteDestination(HomeDetailRoute.self) { _, _ in
                        builds += 1
                        return EmptyView()
                    }
                })
            let expected = """
                root
                ├─ default
                │  ├─ sheet DomainOnlyRoute → destination #1
                │  └─ branches (concurrent)
                │     ├─ branch #1 (String)
                │     │  └─ push NumberedRoute → destination #2
                │     └─ branch #2 (String)
                │        └─ push NumberedRoute → destination #2
                └─ high
                   └─ cover.fade HomeDetailRoute → destination #3
                      └─ sheet DomainOnlyRoute → destination #1
                """
            let event = DepartureLogEvent.mapAdopted(definitions: engine.root.definitions, ownerID: engine.id)
            #expect(event.logLevel == .trace)
            #expect(event.renderedMessage == "[map] ✓ adopted routing map owner=\(engine.id.uuidString.prefix(8))\n\(expected)")
            #expect(event.renderedMessages == [event.renderedMessage])
            #expect(engine.root.definitions.departureMapTrace == expected)
            #expect(builds == 0)
        }

        @Test func largeAdoptedTreeEmitsCompleteMultilineChunksWithoutBuildingViews() {
            var builds = 0
            let engine = RouterEngine(
                routes: RootRouteMap {
                    Branches {
                        for branch in 0..<600 {
                            Branch(branch) { Push(NumberedRoute.self) }
                        }
                    }
                } destinations: {
                    RouteDestination(NumberedRoute.self) { _, _ in
                        builds += 1
                        return EmptyView()
                    }
                })
            let event = DepartureLogEvent.mapAdopted(definitions: engine.root.definitions, ownerID: engine.id)
            let lines = event.renderedMessage.components(separatedBy: "\n")
            let messages = event.renderedMessages

            #expect(lines.count == 1_204)
            #expect(messages.count == 4)
            #expect(messages.map { $0.components(separatedBy: "\n").count } == [400, 400, 400, 4])
            #expect(messages.joined(separator: "\n") == event.renderedMessage)
            #expect(messages.last?.hasSuffix("      └─ branch #600 (Int)\n         └─ push NumberedRoute → destination #1") == true)
            #expect(builds == 0)
        }

        @Test func otherEventsKeepMultilineContextInOneRecord() {
            let event = DepartureLogEvent.routeLookupStarted(routeType: NumberedRoute.self, activePath: "root")
            #expect(event.renderedMessage.contains("\n"))
            #expect(event.renderedMessages == [event.renderedMessage])
        }

        @Test func treeIdentifiesMissingAndConflictingBindingsWithoutPrintingConfiguredIDs() {
            let first = RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
            let second = RouteDestination(DomainOnlyRoute.self) { _, _ in EmptyView() }
            let child = RouteMap(id: "private-scope") {
                Sheet(DomainOnlyRoute.self)
            } destinations: {
                second
            }
            let engine = RouterEngine(
                routes: RootRouteMap(id: "private-root") {
                    Sheet(DomainOnlyRoute.self)
                    Push(HomeDetailRoute.self) { child }
                    Sheet(SettingsRoute.self)
                    Push(SettingsRoute.self)
                    Branches {
                        Branch("private-branch") { Push(NumberedRoute.self) }
                        Branch("private-branch") { Push(NumberedRoute.self) }
                    }
                } destinations: {
                    first
                    RouteDestination(HomeDetailRoute.self) { _, _ in EmptyView() }
                })
            let tree = engine.root.definitions.departureMapTrace
            #expect(tree.contains("sheet DomainOnlyRoute → [destination conflict]"))
            #expect(tree.contains("sheet SettingsRoute → [missing destination] [declaration conflict]"))
            #expect(tree.contains("push NumberedRoute → [missing destination]"))
            #expect(tree.contains("branch #1 (String) [branch conflict]"))
            #expect(!tree.contains("private-"))
        }

        @Test func adoptionTraceRespectsLevelsAndRunsOnceForEachOwner() {
            let previous = Departure.debug
            defer { Departure.debug = previous }
            let engine = RouterEngine(routes: RootRouteMap {})
            Departure.debug = .off
            #expect(!engine.traceMapAdoption())
            Departure.debug = .normal
            #expect(!engine.traceMapAdoption())
            #expect(!engine.hasTracedMapAdoption)
            Departure.debug = .trace
            #expect(engine.traceMapAdoption())
            #expect(engine.hasTracedMapAdoption)
            #expect(!engine.traceMapAdoption())
            engine.configureMap(RootRouteMap {})
            #expect(!engine.traceMapAdoption())
            let other = RouterEngine(routes: RootRouteMap {})
            #expect(other.traceMapAdoption())
        }

        @Test func mapConstructionDoesNotTraceBeforeTheHostAppears() {
            let previous = Departure.debug
            defer { Departure.debug = previous }
            Departure.debug = .trace
            let owner = RootRouter()
            _ = WithRouter(routes: RootRouteMap {}, router: owner) { EmptyView() }
            #expect(!owner.engine.hasTracedMapAdoption)
        }
    }
#endif
