# Getting started

Departure has three moving parts: a `Router`, route values, and declarations that say how a scope presents each route.

## Install the router

Wrap the root of your app with `WithRouter`.

```swift
@main
struct ExampleApp: App {
  var body: some Scene {
    WindowGroup {
      WithRouter {
        NavigationStack { HomeView() }
      }
    }
  }
}
```

## Create and present a route

A route is a value that builds its destination. Declare it on the view that owns its presentation, then request it from the environment router.

```swift
struct ProfileRoute: Route {
  let userID: String

  func destination() -> some View {
    ProfileView(userID: userID)
  }
}

struct HomeView: View {
  @Environment(\.router) private var router

  var body: some View {
    Button("View profile") {
      Task { await router.present(ProfileRoute(userID: "42")) }
    }
    .routes {
      Push(ProfileRoute.self)
    }
  }
}
```

The environment router captures the view's scope. Keeping a copy preserves that origin;
it does not follow whichever pane or tab becomes current later. After the scope leaves
the routing graph, its router becomes inactive. Outside `WithRouter`, the environment
router is inactive and commands do nothing.

Use `Push` inside a `NavigationStack`. `Sheet` and `Cover` present modally and provide a navigation stack around their destination by default.

For an app split into Domain and Feature modules, the route can omit `destination()` and the
feature can supply it separately. See
[Supply a view from a feature module](routing.md#supply-a-view-from-a-feature-module).

Next: [Routing](routing.md)
