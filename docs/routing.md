# Routing

Declare each route on the scope that should present it.

```swift
.routes {
  Push(ProfileRoute.self)
  Sheet(SettingsRoute.self)
  Cover(OnboardingRoute.self)
}
```

`router.present(...)` starts at the active route and uses the closest matching declaration. The same route type may be declared in more than one scope; the nearest owner wins. If no scope owns it, nothing is presented.

## Supply a view from a feature module

A route can live in a top-level Domain module without depending on its feature view. Omit
`destination()` from the route declaration:

```swift
// Domain module
import Departure

public struct SettingsRoute: Route {
  public init() {}
}
```

The feature module imports Domain and supplies the destination:

```swift
// SettingsFeature module
import Departure
import Domain
import SwiftUI

extension SettingsRoute: RouteViewProviding {
  public func destination() -> some View {
    SettingsView()
  }
}
```

Departure chooses a destination in this order:

1. `RouteViewProviding.destination()` when the route conforms to `RouteViewProviding`.
2. The route's existing `Route.destination()` implementation.
3. A diagnostic view naming the route type in Debug builds, or `EmptyView` in Release builds.

Only one module can add the `RouteViewProviding` conformance for a route type. Modules in the same
package use the extension above. Add `@retroactive` to the conformance only when the route belongs
to a different package.

## Styles

| Declaration | Presentation |
| --- | --- |
| `Push` | Pushes onto the nearest `NavigationStack`. |
| `Sheet` | Presents a sheet. |
| `Cover` | Presents a full-screen cover. |

`Sheet` and `Cover` wrap destinations in a `NavigationStack`. Use `providesNavigation: false` when that is not wanted.

```swift
.routes {
  Sheet(SettingsRoute.self, providesNavigation: false)
}
```

`Cover` uses a slide transition by default; choose `.fade` for a cross-dissolve.

```swift
Cover(OnboardingRoute.self, transition: .fade)
```

Fade covers render in a detached host. As with elevated-priority presentations, forward any custom environment values they need with `WithRouter`’s `windowDestination`.

## Route phase

Read `routePhase` when a view needs to react to whether its local route scope is current.

```swift
@Environment(\.routePhase) private var routePhase

SaveButton()
  .disabled(routePhase != .active)
```

## Guard a route

Routes can permit, replace, or reject themselves before they are presented.

```swift
struct ProtectedSettingsRoute: Route {
  let isLoggedIn: Bool

  func resolveRoute() async -> RouteResolution {
    isLoggedIn ? .allow : .reroute(LoginRoute())
  }

  func destination() -> some View { SettingsView() }
}
```

Keep resolution fast. A rerouted route is resolved too, so make sure the flow cannot loop.

## Avoid duplicate destinations

Make a route `Equatable` when its value identifies a destination. If routing finds an equal route on the active path, it stops lookup and unwinds to that route instead of presenting a duplicate.

```swift
struct ReceiptRoute: Route, Equatable {
  let receiptID: UUID

  func destination() -> some View { ReceiptView(id: receiptID) }
}
```

## One declaration per type

Within one scope, the first route declaration for a route type, action interceptor for an action type, and unwind handler for a route type wins. Later duplicates are ignored and emit a runtime warning.

Next: [Actions](actions.md) · [Unwinding](unwinding.md)
