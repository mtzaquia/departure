# Branches

Use branches for selection-based containers such as `TabView`. Each branch keeps its own push path, and the container can make routes discoverable before their branch has been built.

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

Next: [Priority](priority.md)
