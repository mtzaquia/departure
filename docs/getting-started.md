# Getting started

Departure separates domain route data, feature destination builders, and a persistent map. Views connect presentation to their mapped scope.

## Define route data and a destination

```swift
import Departure
import SwiftUI

struct ProfileRoute: Route, Equatable {
  let userID: String
}

@MainActor
enum ProfileFeature {
  static let destination = RouteDestination(ProfileRoute.self) { route, context in
    ProfileView(userID: route.userID, close: context.unwindRoute)
  }
}
```

`RouteDestination` associates the route type with a view builder. The route can live in a Domain module; the feature imports it without adding a conformance or extension to the domain type.

## Compose the map

```swift
let profileRoutes = RouteMap {
  Push(ProfileFeature.destination)
}

let appRoutes = RootRouteMap {
  profileRoutes
  Sheet(SettingsFeature.destination) {
    Push(SettingsFeature.advancedDestination)
  }
}
```

A nested builder declares routes available in that destination's scope. Inserting a `RouteMap` contributes its definitions without introducing another scope. Definitions are fixed for the routing owner's lifetime; view rebuilds do not add or remove them.

## Bind views and request routes

```swift
WithRouter(routes: appRoutes) {
  RoutedNavigationStack { HomeView() }
}

// In HomeView:
@Environment(\.router) private var router

Button("View profile") {
  Task { await router.present(ProfileRoute(userID: "42")) }
}
```

`WithRouter` binds the root automatically. Every destination receives its own bound scope. `RoutedNavigationStack` places `.routing()` at its root. The equivalent manual form remains available:

```swift
NavigationStack { HomeView().routing() }
```

Use `.routing()` inside a custom container when it should own presentation or capture environment values applied within that container. It uses the same scope and takes precedence over automatic wiring.

Sheets, covers, and replacements require a stack only when their content needs one. Departure never adds a navigation container to a destination.

An environment router captures the view's scope. Stored copies retain that origin and become inactive when it leaves the graph. Outside `WithRouter`, commands do nothing.

For deep links and notifications, keep an explicit owner and capture the normal flow when issuing navigation:

```swift
@State private var rootRouter = RootRouter()
WithRouter(routes: appRoutes, router: rootRouter) { HomeView() }
await rootRouter.normal.present(ProfileRoute(userID: "42"))
```

`RootRouter` owns the container. `Router` is a weak scope-bound handle; a saved copy does not retarget itself after suspension or removal.

`normal` captures the normal flow even while a high or critical space covers it. That captured router rejects navigation and action dispatch while covered, protecting a lockscreen from external navigation. `current` captures the top space and carries that space's local authority.

Next: [Routing](routing.md)
