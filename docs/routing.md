# Routing

Declare each route on the scope that should present it.

```swift
.routes {
  Push(ProfileRoute.self)
  Sheet(SettingsRoute.self)
  Cover(OnboardingRoute.self)
}
```

`router.present(...)` starts at the scope captured by that router and uses the closest matching declaration in its branch or enclosing scopes. If the current branch has no match, discovery crawls up to container `Branch(...)` declarations and automatically selects the branch owning the match, including a branch whose view has not been built yet. It does not search arbitrary destination scopes inside sibling stacks. The same route type may be declared in more than one scope; the nearest owner wins. Use `router.branch(...)` to explicitly choose a branch when needed. If no eligible scope owns the route, nothing is presented.

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

The feature module imports Domain and binds the route to a view:

```swift
// SettingsFeature module
import Departure
import Domain
import SwiftUI

let settings = RouteDestination(SettingsRoute.self) { route, context in
  SettingsView()
}

// On the owning view:
.routes {
  Sheet(settings)
}
```

`Push`, `Replace`, `Sheet`, and `Cover` infer the route type from the destination value.
Requests still use domain instances: `await router.present(SettingsRoute())`. Builders can
capture feature dependencies, and the same route type can have different builders in
different declaration scopes. The matched declaration selects the builder; there is no
global registry or extra conformance.

`RouteDestination` and its context are available on this development branch; they are not
yet part of the v2.1.0 release.

### Destination context

Each builder receives typed route data and a `RouteContext`:

| Value | Purpose |
| --- | --- |
| `context.router` | Routes from this destination's own scope. |
| `context.unwindRoute` | Unwinds this exact scope, optionally delivering a payload. |
| `context.presentation.style` | `.push`, `.replace`, `.sheet`, or `.cover(transition)`. |
| `context.presentation.priority` | Effective priority, including the enclosing elevated flow. |
| `context.environment` | Environment snapshot for this rendering, including local routing values. |

A push inside a high-priority cover reports `.push` and `.high`. Metadata describes the
matched presentation after route resolution. Use it to configure your feature's controls:

```swift
let editProfile = RouteDestination(EditProfileRoute.self) { route, context in
  EditProfileView(
    userID: route.userID,
    showsCloseButton: context.presentation.style != .push,
    onClose: { await context.unwindRoute() }
  )
}
```

`EditProfileView` and its parameters are illustrative feature APIs. The context and the
view's environment refer to the same destination scope. Captured routers and unwind actions
remain tied to that scope and become inactive when it leaves the routing graph.

The builder runs on the main actor. Read environment values during builder evaluation;
environment changes reevaluate it. Copy individual values when you need them later, rather
than retaining the context for later environment reads. Read route phase through
`context.environment.routePhase`.
Local presentations inherit their host's environment. Detached hosts retain the existing
`WithRouter(windowDestination:)` forwarding mechanism for custom values; forward those values
onto the supplied destination so its view and context receive the same environment.

### Migrate a provider conformance

`RouteViewProviding` is deprecated. Replace its conformance with a `RouteDestination` value
in the feature module, then change `Sheet(SettingsRoute.self)` to `Sheet(settings)` (or the
corresponding `Push`, `Cover`, or `Replace` declaration). Remove the provider extension when
all its declaration sites use explicit destination values.

Existing APIs continue to build destinations in this order:

1. The matched declaration's explicit `RouteDestination` builder.
2. `RouteViewProviding.destination()` when the route conforms to that protocol.
3. The route's existing `Route.destination()` implementation.
4. A diagnostic view naming the route type in Debug builds, or an empty view in Release builds,
   when the route uses the default `destination()` implementation.

`Route.destination()` (including its default implementation) and `RouteViewProviding` are
deprecated but remain functional. Route-type declaration initializers remain supported without
deprecation. Destination-value initializers preserve the existing `priority:`, `transition:`,
and `providesNavigation:` options and defaults, including automatic modal navigation stacks.

## Styles

| Declaration | Presentation |
| --- | --- |
| `Push` | Pushes onto the nearest `NavigationStack`. |
| `Replace` | Replaces the declaring view's content and clears its descendants without adding a Back entry. |
| `Sheet` | Presents a sheet. |
| `Cover` | Presents a full-screen cover. |

`Replace` needs no `NavigationStack` unless its destination declares pushes. In a `Branch`
map, it changes that branch's selected root while preserving other branches. See
[replacement selections](branches.md#route-across-concurrent-columns) for the split-view workflow.

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

Read `routePhase` when a view needs to react to whether its local scope is current within its participating branch. Several concurrent branches can have active scopes at once; visibility and focus are separate from this phase.

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
