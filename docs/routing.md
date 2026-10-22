# Routing

A map describes where route values can be presented. `router.present(...)` resolves the value, finds the nearest eligible declaration, and coordinates the transition.

## Supply a destination from a feature

```swift
// Domain module
import Departure
public struct SettingsRoute: Route {
  public init() {}
}

// SettingsFeature module
import Departure
import Domain
import SwiftUI

@MainActor
public enum SettingsFeature {
  public static let destination = RouteDestination(SettingsRoute.self) { _, context in
    SettingsView(close: context.unwindRoute)
  }
}
```

Declare the route type in the map, then supply the feature builder through `destinations:`:

```swift
RootRouteMap {
  Sheet(SettingsRoute.self)
} destinations: {
  SettingsFeature.destination
}
```

No fallback view or retroactive conformance is needed. Builders are bound when the root is installed; their views are built later in the destination's own context.

## Compose destination bindings

A feature map can describe routes implemented by other modules and supply only its own builders. The enclosing map completes the missing bindings:

```swift
let settings = RouteMap {
  Sheet(SettingsRoute.self) {
    Push(ProfileRoute.self)
  }
} destinations: {
  SettingsFeature.destination
}

let routes = RootRouteMap {
  settings
} destinations: {
  ProfileFeature.destinations
}
```

`RouteDestinations` composes individual typed builders and other destination collections, including conditionals and loops:

```swift
let destinations = RouteDestinations {
  ProfileFeature.destination
  SettingsFeature.destinations
}
```

All destination contributions from the composed tree form one catalog when the root is installed, including contributions from inactive branches and unpresented destination children. Each route type accepts one destination value. Reusing that value, its copies, or a collection containing it is allowed. Distinct values for the same type report a diagnostic and disable that binding throughout the tree, regardless of composition order. There is no map-specific override precedence. Collections retain entries without evaluating view builders.

A registered builder does not declare a route or expand route discoverability. Missing builders are diagnosed during root installation. Requests matching an unbound declaration leave navigation unchanged and do not fall back to another declaration of that type.

## Choose a style and children

```swift
RootRouteMap {
  Push(ProfileRoute.self)
  Replace(MessageRoute.self) {
    Push(AttachmentRoute.self)
  }
  Sheet(SettingsRoute.self)
  Cover(OnboardingRoute.self, transition: .fade)
} destinations: {
  ProfileFeature.destination
  MessageFeature.destinations
  SettingsFeature.destination
  OnboardingFeature.destination
}
```

| Declaration | Presentation |
| --- | --- |
| `Push` | Pushes in an explicitly supplied navigation stack. |
| `Replace` | Changes the declaring scope's selected content without a Back entry. |
| `Sheet` | Presents a sheet. |
| `Cover` | Presents a cover, using `.slide` by default or `.fade`. |

All four declarations accept route types and optional child declarations. View builders belong in `destinations:`. Destinations explicitly construct stacks when needed. A replacement clears its descendants and keeps other branch paths. Fade covers use detached hosts; forward custom environment values through `WithRouter`'s `windowDestination` as described in [Priority](priority.md).

Reusable `RouteMap` values compose in ordinary builders. `ModalRouteMap` composes sheets and covers and can supply destination builders. Root-only `HighPriority` and `CriticalPriority` groups accept modal declarations and modal maps; their entries' children accept ordinary declarations and maps.

## Connect pushes to a navigation stack

Put `.routing()` on the content **inside** a stack that your root view or destination creates:

```swift
WithRouter(routes: appRoutes) {
  NavigationStack {
    RootView()
      .routing()
  }
}
```

Use the same placement in a sheet or cover destination, including stacks that bind their own path or declare native value destinations. `WithRouter` and `RouteView` bind scopes automatically, but an outside modifier cannot install a push destination inside a stack created by its content. On iOS, a push requested from that outside automatic host logs a Departure warning showing the required placement.

A pushed destination already inside its parent's stack can declare push children without calling `.routing()`: its automatic host uses the surrounding stack. `NavigationStack { WithRouter(routes: appRoutes) { RootView() } }` also uses the surrounding stack. Sheet and cover destinations without push children do not need a stack.

One explicit host takes precedence over the automatic host; removing it restores automatic hosting when that host is inside a stack. Two explicit hosts in the same scope still report a conflict and disable presentation until one remains. Branches keep their own hosts through `.routing(branchValue)` and selection through `.routing(branch: $selection)`; see [Branches](branches.md).

## Use destination context

The builder receives route data and `RouteContext`:

```swift
RouteDestination(EditorRoute.self) { route, context in
  EditorView(
    documentID: route.documentID,
    close: context.unwindRoute,
    presentation: context.presentation
  )
}
```

`context.router` and `context.unwindRoute` belong to this destination's scope. `context.presentation.style` reports push, replace, sheet, or cover; `.priority` reports its effective priority. `context.environment` contains the values supplied to the destination and refreshes when they change. The builder can choose wrapping content directly using that context.

## Find the nearest eligible declaration

A scoped request searches its own branch and enclosing scopes. The same type may occur in several scopes; the nearest eligible owner wins. Duplicate route types at one scope report a diagnostic and disable that key, just like duplicate hooks. A conflict stops lookup; it cannot fall back to an ancestor or sibling declaration. Duplicate branch values disable that branch. Distinct declarations remain available.

When no local match exists, discovery can select another mapped branch before that branch's view is built. It does not search arbitrary destination scopes in sibling stacks. `router.branch(...)` chooses a branch explicitly and never falls back to siblings. Knowing a nested definition does not make it available before its parent destination exists.

Modal lanes are shared across branches. Presenting a branch-root modal replaces a modal in that lane while retaining pushed content. A modal's own child declarations can create another modal lane. See [Branches](branches.md).

## Resolve guarded routes and stop at equality

```swift
struct ProtectedSettingsRoute: Route {
  let isLoggedIn: Bool
  func resolveRoute() async -> RouteResolution {
    isLoggedIn ? .allow : .reroute(LoginRoute())
  }
}
```

Resolution may `.allow`, `.reroute`, or `.drop`. Every rerouted value is resolved too. Make the chain finite.

Presentations are admitted one at a time through resolution, rerouting, and insertion or reuse in routing state. If a resolver suspends, a newer attempt waits instead of overtaking it. Only the latest waiting attempt is retained; an attempt superseded before admission returns without resolving. Each admitted request continues in its original caller's task, preserving cancellation and task-local values.

A presentation also waits for ongoing unwind teardown and any required parent host. Superseding a presentation waiting for teardown or its parent host prevents its pending insertion; committed teardown still completes. Unwind returns after its own teardown independently of the next resolver. `await router.present(...)` completes after insertion, reuse, or rejection, without waiting for SwiftUI to display the destination.

Make a route `Equatable` when its value identifies a destination. An equal current route stops; an eligible equal ancestor is retained and its descendants unwind. Replacement equality is limited to the selected slot, so an equal push elsewhere does not become that replacement.

Removal performed to present a route does not invoke unwind handlers. This includes ancestor crawlback, equality reuse, and replacement. The retained equal destination keeps its existing route value and view instance.

## Observe route phase

Read `@Environment(\.routePhase)` to determine whether a scope is a current endpoint of a participating path in the top space. Concurrent branches may each have an active endpoint. A shared modal makes scopes outside its subtree inactive; covered and removed scopes are always inactive.

Live membership and phase answer different questions. Any live scope in the top space may issue commands, including inactive ancestors and unselected branches. Covered and removed scopes cannot. Neither command eligibility nor phase requires a mounted host, and phase does not imply focus or physical visibility.

Next: [Actions](actions.md) · [Unwinding](unwinding.md)
