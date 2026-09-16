# Branches

Branches are named routing scopes hosted by a container. Use exclusive selection for `TabView`, or concurrent participation for a split view. Each branch keeps its own push path, and the container can make routes discoverable before their branch has been built.

```swift
enum AppTab: Hashable, Sendable {
  case home
  case wallet
}

struct RootView: View {
  @State private var tab: AppTab = .home

  var body: some View {
    TabView(selection: $tab) {
      NavigationStack { HomeView().routeBranch(AppTab.home) }
        .tag(AppTab.home)

      NavigationStack { WalletView().routeBranch(AppTab.wallet) }
        .tag(AppTab.wallet)
    }
    .routes(branch: $tab) {
      Cover(LoginRoute.self)
      Branch(.home) { Push(HomeDetailRoute.self) }
      Branch(.wallet) { Sheet(TransactionRoute.self) }
    }
  }
}
```

Read the scoped router from the environment and explicitly target another branch:

```swift
await router.branch(AppTab.wallet).present(TransactionRoute())
```

Obtaining a branch router does not change selection. After a route is resolved and
accepted in that branch, Departure selects it before presenting the destination.
Rejected routes, missing declarations, and reroutes to common ancestors leave the
target selection unchanged. Plain `router.present(...)` searches its branch and
enclosing scopes first, then discovers matching container `Branch(...)` declarations
and automatically selects their branch. This also works before the matching host
has been built. Discovery does not search arbitrary destinations inside sibling stacks.
An explicit `router.branch(...)` target does not fall back to another branch when
its branch has no matching declaration.

A branch router belongs to the nearest enclosing container. It remains usable after
the requesting destination is dismissed, and can address a branch whose view has
not been built yet. Removing its owning container makes it inactive. Chain `branch(...)`
calls to address an already-declared nested container.

## Choose where to declare a route

- Declare a route with `.routes { ... }` inside a feature when it only needs to be found while that feature is active.
- Put it in the container's `Branch(...)` map when a request should select an inactive branch or the branch may not have been built yet. The matching `.routeBranch(...)` host adopts the declaration and presents it.
- Declare the same route in both places only deliberately. A local declaration takes precedence, which supports a feature-specific presentation or a view reused outside the branched container. Ordinary branch routing does not require duplicate declarations.

Declarations outside `Branch(...)` belong to the container, making them useful for flows such as login that are available above every tab.

Branches keep independent push paths, but share modal presentations. A sheet or cover from one branch replaces a current modal from another branch.

To clear the current branch back to its root without leaving the container:

```swift
await router.unwind(to: .nearestBranch)
```

## Route across concurrent columns

Set `concurrent: true` when branches participate together. Use the container's preferred
compact-column binding to reveal a routed destination on a phone:

Keep `concurrent` enabled across size classes. It describes a split container even when
only one column is visible. Departure detects registered hosts and waits for missing
ones automatically. Host registration cannot determine participation: a tab container
can also retain several registered hosts while only its selected branch participates.

```swift
struct LibraryView: View {
  @State private var column = NavigationSplitViewColumn.sidebar

  var body: some View {
    NavigationSplitView(preferredCompactColumn: $column) {
      NavigationStack {
        SidebarView().routeBranch(NavigationSplitViewColumn.sidebar)
      }
    } content: {
      NavigationStack {
        CollectionView().routeBranch(NavigationSplitViewColumn.content)
      }
    } detail: {
      NavigationStack {
        DetailView().routeBranch(NavigationSplitViewColumn.detail)
      }
    }
    .routes(branch: $column, concurrent: true) {
      Branch(.sidebar) { Push(LibrarySettingsRoute.self) }
      Branch(.content) { Push(CollectionRoute.self) }
      Branch(.detail) {
        Push(CoffeeDetailRoute.self)
        Cover(PreviewRoute.self)
      }
    }
  }
}
```

A sidebar action can call:

```swift
await router.branch(NavigationSplitViewColumn.detail)
  .present(CoffeeDetailRoute(coffeeID: id))
```

The detail branch receives the route and the compact-column binding becomes `.detail`.
The other branches retain their push paths. The app owns column visibility, widths,
and adaptive layout; hiding a column does not clear its navigation state. An app-defined
branch enum can also be adapted to the container’s selection or visibility bindings.

Each concurrent branch’s current scope can read `routePhase == .active`. A shared modal
suspends the other branches. Sheets and covers retain their existing modal presentation
behavior; branch ownership does not confine them to a column’s bounds.

Changing one branch does not infer changes to others. The app must coordinate selections
that depend on each other. Replaceable root selection is not implemented in this slice;
`Push` retains its existing navigation behavior.

The [split-view sample](../SampleApp/SampleApp/Views/SplitBranchesView.swift) demonstrates
three concurrent columns, targeted pushes, and a detail-owned cover.

Next: [Priority](priority.md)
