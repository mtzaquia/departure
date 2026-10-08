import Departure
import SwiftUI

struct SplitBranchesRoute: Route {

}

struct SplitBranchesView: View {
    @State private var column = NavigationSplitViewColumn.sidebar
    @State private var visibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $column) {
            NavigationStack {
                SplitBranchPane(column: .sidebar)
                    .routing(NavigationSplitViewColumn.sidebar)
            }
        } content: {
            NavigationStack {
                SplitBranchPane(column: .content)
                    .routing(NavigationSplitViewColumn.content)
            }
        } detail: {
            NavigationStack {
                SplitBranchPane(column: .detail)
                    .routing(NavigationSplitViewColumn.detail)
            }
        }
        .routing(branch: $column)
    }
}

private struct SplitBranchPane: View {
    let column: NavigationSplitViewColumn
    @Environment(\.router) private var router
    @Environment(\.routePhase) private var phase

    private func controlID(_ base: String) -> String {
        column == .sidebar ? base : base + (column == .content ? ".content" : ".detail")
    }

    var body: some View {
        List {
            Section("Concurrent branches") {
                Text("Each column owns a path. Targeting a neighbor preserves the other paths and reveals the destination on a phone.")
                Text("Local phase: \(phase == .active ? "active" : "inactive")")
            }
            Section("Route to another column") {
                Button("Show content") {
                    Task { await router.branch(NavigationSplitViewColumn.content).present(SplitPaneRoute(column: .content)) }
                }
                .accessibilityIdentifier(controlID(SampleAppAccessibility.splitShowContent))
                Button("Show detail") {
                    Task { await router.branch(NavigationSplitViewColumn.detail).present(SplitPaneRoute(column: .detail)) }
                }
                .accessibilityIdentifier(controlID(SampleAppAccessibility.splitShowDetail))
                Button("Cover from detail") {
                    Task { await router.branch(NavigationSplitViewColumn.detail).present(SplitPreviewRoute()) }
                }
                .accessibilityIdentifier(controlID(SampleAppAccessibility.splitCoverDetail))
            }
            Section("Replace selected content") {
                Text("Select a detail root without adding a Back entry. A new selection clears its child navigation and keeps the other columns.")
                Button("Select detail") {
                    Task { await router.branch(NavigationSplitViewColumn.detail).present(SplitSelectionRoute(number: 1)) }
                }
                .accessibilityIdentifier(controlID(SampleAppAccessibility.splitSelectDetail))
            }
        }
        .navigationTitle(column == .sidebar ? "Sidebar" : column == .content ? "Content" : "Detail")
    }
}

private struct SplitPaneRoute: Route, Equatable {
    let column: NavigationSplitViewColumn

}

private struct SplitPaneDestination: View {
    let column: NavigationSplitViewColumn
    @Environment(\.unwindRoute) private var unwindRoute
    @Environment(\.router) private var router

    var body: some View {
        VStack(spacing: 20) {
            Text(column == .content ? "Content destination" : column == .detail ? "Detail destination" : "Sidebar destination")
                .accessibilityIdentifier(column == .content ? SampleAppAccessibility.splitContentDestination : column == .detail ? SampleAppAccessibility.splitDetailDestination : "sample.split.sidebar-destination")
            Button("Done") { Task { await unwindRoute() } }
                .accessibilityIdentifier(column == .content ? SampleAppAccessibility.splitContentDone : column == .detail ? SampleAppAccessibility.splitDetailDone : "sample.split.sidebar-done")
            if column == .detail {
                Button("Preview") { Task { await router.present(SplitPreviewRoute()) } }
                    .accessibilityIdentifier(SampleAppAccessibility.splitCoverDetail + ".destination")
            }
            Button("Show sidebar") {
                Task { await router.branch(NavigationSplitViewColumn.sidebar).present(SplitPaneRoute(column: .sidebar)) }
            }
            .accessibilityIdentifier(SampleAppAccessibility.splitReturnSidebar)
        }
        .padding()
        .navigationTitle(column == .content ? "Content selection" : column == .detail ? "Detail selection" : "Sidebar selection")
    }
}

private struct SplitSelectionRoute: Route, Equatable {
    let number: Int

}

private struct SplitSelectionDestination: View {
    let number: Int
    @Environment(\.router) private var router
    @Environment(\.unwindRoute) private var unwindRoute
    @Environment(\.routePhase) private var phase

    var body: some View {
        List {
            Section("Selected root") {
                Text("Detail selection \(number)")
                    .accessibilityIdentifier(SampleAppAccessibility.splitSelection)
                Text("Local phase: \(phase == .active ? "active" : "inactive")")
                Button("Select next") { Task { await router.present(SplitSelectionRoute(number: number + 1)) } }
                    .accessibilityIdentifier(SampleAppAccessibility.splitSelectNext)
                Button("Open child") { Task { await router.present(SplitSelectionChildRoute(number: number)) } }
                    .accessibilityIdentifier(SampleAppAccessibility.splitSelectionOpenChild)
                Button("Preview") { Task { await router.present(SplitPreviewRoute()) } }
                    .accessibilityIdentifier(SampleAppAccessibility.splitSelectionPreview)
                Button("Clear selection") { Task { await unwindRoute() } }
                    .accessibilityIdentifier(SampleAppAccessibility.splitSelectionClear)
            }
        }
        .navigationTitle("Selected detail")
        .routing()
    }
}

private struct SplitSelectionChildRoute: Route, Equatable {
    let number: Int

}

private struct SplitSelectionChildDestination: View {
    let number: Int
    @Environment(\.router) private var router
    @Environment(\.unwindRoute) private var unwindRoute

    var body: some View {
        List {
            Text("Child of selection \(number)")
                .accessibilityIdentifier(SampleAppAccessibility.splitSelectionChild)
            Button("Replace from child") { Task { await router.present(SplitSelectionRoute(number: number + 1)) } }
                .accessibilityIdentifier(SampleAppAccessibility.splitSelectionChildReplace)
            Button("Done") { Task { await unwindRoute() } }
                .accessibilityIdentifier(SampleAppAccessibility.splitSelectionChildDone)
        }
        .navigationTitle("Selection child")
    }
}

private struct SplitPreviewRoute: Route {

}

private struct SplitPreview: View {
    @Environment(\.unwindRoute) private var unwindRoute
    var body: some View {
        VStack(spacing: 20) {
            Text("Detail-owned cover")
                .accessibilityIdentifier(SampleAppAccessibility.splitCover)
            Text("Cover keeps its existing full-screen presentation behavior.")
            Button("Done") { Task { await unwindRoute() } }
                .accessibilityIdentifier(SampleAppAccessibility.splitCoverDone)
        }
        .padding()
    }
}


private enum SplitDestinations {
    static let splitBranchesRoute = RouteDestination(SplitBranchesRoute.self) { route, context in
        SplitBranchesView()
    }
    static let splitPaneRoute = RouteDestination(SplitPaneRoute.self) { route, context in
        let column = route.column
        SplitPaneDestination(column: column)
    }
    static let splitSelectionRoute = RouteDestination(SplitSelectionRoute.self) { route, context in
        let number = route.number
        SplitSelectionDestination(number: number)
    }
    static let splitSelectionChildRoute = RouteDestination(SplitSelectionChildRoute.self) { route, context in
        let number = route.number
        SplitSelectionChildDestination(number: number)
    }
    static let splitPreviewRoute = RouteDestination(SplitPreviewRoute.self) { route, context in
        SplitPreview()
    }
}


enum SplitBranchMap {
    static let destination = RouteDestination(SplitBranchesRoute.self) { _, _ in SplitBranchesView() }
    static let routes = RouteMap {
        Branches(concurrent: true) {
            Branch(NavigationSplitViewColumn.sidebar) { Push(SplitDestinations.splitPaneRoute) }
            Branch(NavigationSplitViewColumn.content) { Push(SplitDestinations.splitPaneRoute) }
            Branch(NavigationSplitViewColumn.detail) {
                Push(SplitDestinations.splitPaneRoute)
                Replace(SplitDestinations.splitSelectionRoute) { Push(SplitDestinations.splitSelectionChildRoute) }
                Cover(SplitDestinations.splitPreviewRoute)
            }
        }
    }
}
