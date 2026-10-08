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

A route carries a navigation request and its data. Bind it to a feature view using
`RouteDestination`, declare that destination on the view that owns its presentation, then
request the route from the environment router.

```swift
struct ProfileRoute: Route {
  let userID: String
}

struct HomeView: View {
  @Environment(\.router) private var router
  private static let profile = RouteDestination(ProfileRoute.self) { route, context in
    ProfileView(userID: route.userID)
  }

  var body: some View {
    Button("View profile") {
      Task { await router.present(ProfileRoute(userID: "42")) }
    }
    .routes {
      Push(Self.profile)
    }
  }
}
```

The environment router captures the view's scope. Keeping a copy preserves that origin;
it does not follow whichever pane or tab becomes current later. After the scope leaves
the routing graph, its router becomes inactive. Outside `WithRouter`, the environment
router is inactive and commands do nothing.

Use `Push` inside a `NavigationStack`. `Sheet` and `Cover` present modally and provide a navigation stack around their destination by default.

`RouteDestination` is available on this development branch and is not yet in v2.1.0.
Existing `Route.destination()` implementations and `RouteViewProviding` conformances are
deprecated but remain functional. Route-type presentation declarations remain supported.

For an app split into Domain and Feature modules, define the route in Domain and its
`RouteDestination` in the feature. See
[Supply a view from a feature module](routing.md#supply-a-view-from-a-feature-module).

Next: [Routing](routing.md)
