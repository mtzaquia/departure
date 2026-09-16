import Departure
import SwiftUI

struct SplitBranchesRoute: Route {
    func destination() -> some View { SplitBranchesView() }
}

struct SplitBranchesView: View {
    @State private var column = NavigationSplitViewColumn.sidebar
    @State private var visibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $column) {
            NavigationStack {
                SplitBranchPane(column: .sidebar)
                    .routeBranch(NavigationSplitViewColumn.sidebar)
            }
        } content: {
            NavigationStack {
                SplitBranchPane(column: .content)
                    .routeBranch(NavigationSplitViewColumn.content)
            }
        } detail: {
            NavigationStack {
                SplitBranchPane(column: .detail)
                    .routeBranch(NavigationSplitViewColumn.detail)
            }
        }
        .routes(branch: $column, concurrent: true) {
            Branch(.sidebar) { Push(SplitPaneRoute.self) }
            Branch(.content) { Push(SplitPaneRoute.self) }
            Branch(.detail) {
                Push(SplitPaneRoute.self)
                Cover(SplitPreviewRoute.self, providesNavigation: false)
            }
        }
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
        }
        .navigationTitle(column == .sidebar ? "Sidebar" : column == .content ? "Content" : "Detail")
    }
}

private struct SplitPaneRoute: Route, Equatable {
    let column: NavigationSplitViewColumn
    func destination() -> some View { SplitPaneDestination(column: column) }
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

private struct SplitPreviewRoute: Route {
    func destination() -> some View { SplitPreview() }
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
