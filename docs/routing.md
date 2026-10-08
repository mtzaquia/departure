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

Declare `Sheet(SettingsFeature.destination)` in the application map. Each declaration has a destination builder; no fallback view or retroactive conformance is needed. Different occurrences of the same route type may use different builders.

## Choose a style and children

```swift
RootRouteMap {
  Push(ProfileFeature.destination)
  Replace(MessageFeature.destination) {
    Push(MessageFeature.attachmentDestination)
  }
  Sheet(SettingsFeature.destination)
  Cover(OnboardingFeature.destination, transition: .fade)
}
```

| Declaration | Presentation |
| --- | --- |
| `Push` | Pushes in an explicitly supplied navigation stack. |
| `Replace` | Changes the declaring scope's selected content without a Back entry. |
| `Sheet` | Presents a sheet. |
| `Cover` | Presents a cover, using `.slide` by default or `.fade`. |

Destinations explicitly construct stacks when needed. A replacement clears its descendants and keeps other branch paths. Fade covers use detached hosts; forward custom environment values through `WithRouter`'s `windowDestination` as described in [Priority](priority.md).

Reusable `RouteMap` values compose in ordinary builders. Use `ModalRouteMap` to compose high/critical entries: only sheets, covers, and other modal maps can appear in its base builder. Their children still support pushes, replacements, branches, and ordinary maps.

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

Make a route `Equatable` when its value identifies a destination. An equal current route stops; an eligible equal ancestor is retained and its descendants unwind. Replacement equality is limited to the selected slot, so an equal push elsewhere does not become that replacement.

## Observe route phase

Read `@Environment(\.routePhase)` to determine whether a scope is a current endpoint of a participating path in the top space. Concurrent branches may each have an active endpoint. A shared modal makes scopes outside its subtree inactive; covered and removed scopes are always inactive.

Live membership and phase answer different questions. Any live scope in the top space may issue commands, including inactive ancestors and unselected branches. Covered and removed scopes cannot. Neither command eligibility nor phase requires a mounted host, and phase does not imply focus or physical visibility.

Next: [Actions](actions.md) · [Unwinding](unwinding.md)
