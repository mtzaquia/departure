# Branches

Use branches for selection-based containers such as `TabView`. Each branch keeps its own push path while the container supplies the complete route map, including lazy tabs that have not been built yet.

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

When a route belongs to another branch, Departure selects that branch before presenting it.

Declarations outside `Branch(...)` belong to the container, making them useful for flows such as login that are available above every tab. `Branch(...)` declarations are its discovery map. Explicit `.routes { ... }` declarations on a `.routeBranch(...)` view take precedence, so the same view can declare its own routes and also be reused outside a branched container.

Branches keep independent push paths, but share modal presentations. A sheet or cover from one branch replaces a current modal from another branch.

To clear the current branch back to its root without leaving the container:

```swift
await router.unwind(to: .nearestBranch)
```

Next: [Priority](priority.md)
