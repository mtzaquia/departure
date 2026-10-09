import Departure
import SwiftUI

struct IndependentSpaceProbeRoot: View {
    @Environment(\.router) private var router
    var body: some View {
        Button("Open high sheet") { Task { await router.present(SpaceProbeHigh()) } }
            .accessibilityIdentifier("sample.spaces.open-high")
    }
}

enum IndependentSpaceProbeMap {
    static func root(owner: RootRouter) -> RootRouteMap {
        RootRouteMap {
            Sheet(RouteDestination(SpaceProbeDefault.self) { _, context in
                VStack {
                    Text("Default after high removal").accessibilityIdentifier("sample.spaces.default")
                    Button("Done") { Task { await context.unwindRoute() } }
                }
            })
        } highPriority: {
            Sheet(RouteDestination(SpaceProbeHigh.self) { _, context in
                NavigationStack {
                    VStack(spacing: 20) {
                        Text("High space root").accessibilityIdentifier("sample.spaces.high-root")
                        Button("Push within high") { Task { await context.router.present(SpaceProbeDetail()) } }
                            .accessibilityIdentifier("sample.spaces.push")
                        Button("Close high, then present default") {
                            Task {
                                if await owner.dismissSpace(.high) {
                                    await owner.current.present(SpaceProbeDefault())
                                }
                            }
                        }.accessibilityIdentifier("sample.spaces.chain")
                        Button("Open critical") { Task { await context.router.present(SpaceProbeCritical()) } }
                            .accessibilityIdentifier("sample.spaces.open-critical")
                        Button("Close high") { Task { await context.unwindRoute() } }
                            .accessibilityIdentifier("sample.spaces.close-high")
                    }
                    .routing()
                }
            }) {
                Push(RouteDestination(SpaceProbeDetail.self) { _, context in
                    Button("Reset high to its root") { Task { await context.router.unwind(to: .root) } }
                        .accessibilityIdentifier("sample.spaces.reset")
                })
            }
        } criticalPriority: {
            Cover(RouteDestination(SpaceProbeCritical.self) { _, context in
                VStack(spacing: 20) {
                    Text("Critical space root").accessibilityIdentifier("sample.spaces.critical-root")
                    Button("Remove covered high") { Task { await owner.dismissSpace(.high) } }
                        .accessibilityIdentifier("sample.spaces.remove-covered-high")
                    Button("Close critical") { Task { await context.unwindRoute() } }
                        .accessibilityIdentifier("sample.spaces.close-critical")
                }
            })
        }
    }
}

private struct SpaceProbeHigh: Route, Equatable {}
private struct SpaceProbeDetail: Route, Equatable {}
private struct SpaceProbeDefault: Route, Equatable {}
private struct SpaceProbeCritical: Route, Equatable {}
