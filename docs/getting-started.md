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
  @Environment(Router.self) private var router

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

Use `Push` inside a `NavigationStack`. `Sheet` and `Cover` present modally and provide a navigation stack around their destination by default.

Next: [Routing](routing.md)
