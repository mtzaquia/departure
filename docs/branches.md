# Branches

`Branches` accepts only `Branch` declarations. Put routes shared by the container beside the group in its enclosing map; declare branch-local routes inside each `Branch`.

A branch owns an independent navigation path. `Branches(concurrent:)` declares whether one branch or several branches participate at once; all branches share their enclosing modal lane.

A scope accepts exactly one `Branches` group, including through composed `RouteMap` values. Declare `Branch` values inside that group. To compose features, put their maps inside the corresponding `Branch` builders. Multiple groups report a diagnostic and disable that scope's branch container; sibling route declarations remain available.

## Map tabs and connect selection

```swift
enum AppTab: Hashable, Sendable { case home, wallet }

let routes = RootRouteMap {
  Cover(LoginFeature.destination)
  Branches {
    Branch(AppTab.home) { Push(HomeFeature.detailDestination) }
    Branch(AppTab.wallet) { Sheet(WalletFeature.transactionDestination) }
  }
}

struct RootView: View {
  @State private var tab: AppTab = .home
  var body: some View {
    TabView(selection: $tab) {
      NavigationStack { HomeView().routing(AppTab.home) }
        .tag(AppTab.home)
      NavigationStack { WalletView().routing(AppTab.wallet) }
        .tag(AppTab.wallet)
    }
    .routing(branch: $tab)
  }
}
```

`WithRouter(routes: routes) { RootView() }` seeds the scope. `.routing(branchValue)` enters its mapped branch and binds presentation. `.routing(branch: binding)` connects the container's presentation and selection to its existing mapped scope; a separate `.routing()` is unnecessary. `Branches` defaults to exclusive participation and the first declared branch supplies the initial selection when there is no binding.

The model owns one selected value. When connected to a view, the container accepts exactly one `.routing(branch:)` binding owner. Multiple owners report a diagnostic, retain the current selection, and disable selection changes until one remains. Removing a binding retains the model's selection and branch history. Once the scope leaves the live tree, outgoing attachments cannot synchronize or restore its bindings. Plain `.routing()` hosts and branch-content `.routing(branchValue)` modifiers do not own the container's selection.

Use branch values representable by the binding's selection type. For example, enum branch values should use a binding to that enum rather than to strings. An incompatible write reports the branch value and both types, rejects activation, and leaves navigation unchanged. Optional bindings can represent their corresponding nonoptional branch values.

Definitions outside `Branch` belong to the enclosing container. Route builders can contain further branch maps, allowing nested containers without a view registration step.

## Target a branch

```swift
await router.branch(AppTab.wallet).present(TransactionRoute())
await router.unwind(to: .nearestBranch)
```

Obtaining a branch router leaves selection unchanged. An accepted route activates its branch; rejected requests, missing declarations, and reroutes to common ancestors do not activate the original target. Plain requests discover mapped branches after local and enclosing matches.

A branch router belongs to its enclosing container, so it survives dismissal of the requesting destination. Removing that container makes it inactive. Chained `branch(...)` calls address mapped nested containers. An explicit target does not search sibling branches.

## Keep concurrent columns

```swift
let columns = RouteMap {
  Branches(concurrent: true) {
    Branch(NavigationSplitViewColumn.sidebar) { Push(LibraryFeature.settingsDestination) }
    Branch(NavigationSplitViewColumn.content) { Push(CollectionFeature.destination) }
    Branch(NavigationSplitViewColumn.detail) {
      Replace(MessageFeature.destination) {
        Push(MessageFeature.attachmentDestination)
      }
      Cover(PreviewFeature.destination)
    }
  }
}

NavigationSplitView(preferredCompactColumn: $column) {
  NavigationStack { SidebarView().routing(NavigationSplitViewColumn.sidebar) }
} content: {
  NavigationStack { CollectionView().routing(NavigationSplitViewColumn.content) }
} detail: {
  NavigationStack { DetailView().routing(NavigationSplitViewColumn.detail) }
}
.routing(branch: $column)
```

Keep concurrency enabled across size classes. It describes the container, independently of how many columns SwiftUI currently displays. Targeting a column updates the connected compact-column binding and retains the other paths. The app controls visibility, widths, and adaptive layout.

A branch's root replacement changes its selection without a Back entry. A different value clears that slot's descendants; an equal value retains its scope and unwinds descendants. Removing it reveals the original branch content. Other columns retain their paths.

A sheet or cover in one branch replaces another modal in the same lane. Modals are not confined to column bounds. Nested modal destinations create the next lane, which remains shared by their own branches.

The [split-view sample](../SampleApp/SampleApp/Views/SplitBranchesView.swift) exercises targeted pushes, replacement selections, and detail-owned covers.

Next: [Priority](priority.md)
