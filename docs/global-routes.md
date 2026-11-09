# Global routes

Use a root-only `GlobalMap` to declare shared sheets and covers once. Every live route can request them, and Departure presents them above the foreground flow in the existing window.

## Declare shared destinations

```swift
let routes = RootRouteMap {
  Sheet(CheckoutRoute.self)
  GlobalMap {
    Sheet(SecondFactorRoute.self)
    Cover(PasscodeRoute.self, transition: .fade) {
      Sheet(PasscodeHelpRoute.self)
    }
  }
} destinations: {
  CheckoutFeature.destination
  SecondFactorFeature.destination
  PasscodeFeature.destination
  PasscodeFeature.helpDestination
}
```

`GlobalMap` accepts `Sheet`, `Cover`, and reusable `ModalRouteMap` values. Their children use ordinary declarations and feature maps. Global groups are accepted only in `RootRouteMap`; consumers need no extra presentation attachments. A destination creating a navigation stack still follows the usual `.routing()` placement rule. Sheets can use [compact adaptation](routing.md) independently of global availability.

Global requests use the same `await router.present(...)` API as local navigation. They preserve the invoking flow instead of crawling back to the catalog root. A single 2FA declaration can serve Checkout and Settings at different times; each presentation has its own route instance and state.

An equal global already in foreground ancestry is reused and its descendants are removed. A new value for the current global replaces that occurrence in its existing slot. A different global presents above the foreground. Global availability does not make the destination a singleton or protect it from ordinary ancestor navigation.

Global route types cannot also be declared locally in the composed tree. Such collisions, duplicate global declarations, and conflicting destination builders report diagnostics and disable the ambiguous type. Registering a destination builder alone does not make a route global.

## Keep existing priority declarations

`HighPriority` and `CriticalPriority` are deprecated compatibility type aliases for `GlobalMap`. Existing declarations keep compiling with deprecation warnings, including composed `ModalRouteMap` values and each entry's local child definitions. Both aliases are accepted only at the root and use the same global behavior:

```swift
RootRouteMap {
  HighPriority { Sheet(SecondFactorRoute.self) }
  CriticalPriority { Cover(PasscodeRoute.self, transition: .fade) }
}
```

The names no longer establish a priority order or create separate windows. Either group can present above the foreground flow, including another global route. Use `GlobalMap` for new declarations, and let the app control when navigation is allowed.

The remaining legacy APIs also compile with deprecation warnings. Their compatibility behavior is deliberately limited:

| Legacy API | Compatibility behavior | Replacement |
| --- | --- | --- |
| `RoutePriority` | Retains its cases, raw values, and comparison; has no routing effect. | Declare shared routes in `GlobalMap`. |
| `RoutePresentation.priority` | Always returns `.default`, including for globals. | Read `isGlobal` when checking global availability. |
| `RootRouter.default` | Returns `current`, with no priority filtering. | Use `root` for the permanent app root or `current` for the foreground scope. |
| `Router.dismissSpace()`, `RootRouter.dismissSpace(_:)`, `RootRouter.dismissSpaces()` | Emit a runtime warning, return `false`, and leave navigation unchanged. | Use scoped unwinds, `unwindRoute`, or `resetToRoot()` for the intended dismissal. |
| `WithRouter(..., windowDestination:)` | Creates the routing host; ignores the customizer without storing or evaluating it. | Configure the presenting hierarchy or individual destination builders. |

Space-dismissal warnings remain available in Release builds and with `Departure.debug = .off`. Move app policy and any required cleanup to the replacement operations before relying on those legacy calls.

## Own navigation and dismissal rules

Consumers decide which navigation requests their app may send. Any live scope can issue presentations, actions, unwinds, and resets, including while another route covers it. A local request follows its requesting scope's ordinary lookup; it does not search a foreground global's child declarations on behalf of a covered caller. Use the destination's own router to request its declared children.

An ancestor unwind or reset can remove global presentations. A local presentation may crawl back through them to reach its declaration. `routePhase` describes navigation position and does not block commands. Gate those requests in app state, route resolution, action interceptors, or feature controls when the app requires a particular policy.

Destination implementations also control interactive dismissal. For example:

```swift
NavigationStack {
  PasscodeView()
    .routing()
}
.interactiveDismissDisabled()
```

This modifier controls native gestures; it does not restrict router commands. Departure reconciles native dismissal against the exact occurrence that left. The library supplies no dismissal-protection modifier or protected-route metadata.

## Dismiss and continue a flow

Use the ordinary captured dismissal action:

```swift
RouteDestination(PasscodeRoute.self) { _, context in
  Button("Unlock") {
    Task { await context.unwindRoute() }
  }
}
```

Dismissal actions retain exact instance identity. An old callback cannot close a replacement route. Await dismissal before continuing from a surviving router, and retain ordinary typed unwind handlers to receive results from shared authentication flows.

For notifications or deep links, keep a `RootRouter`. `rootRouter.root` captures the permanent app root; `rootRouter.current` captures the foreground scope at access time. Both may request globals. A stored scoped router never retargets after its source leaves navigation; removed scopes cannot issue commands.

## Inherit presentation configuration

Sheets, slide covers, and fade covers use the presenting SwiftUI hierarchy in the current window. Set shared environment values above `WithRouter` or at the intended presenting scope. `RouteContext.environment` reads the destination's actual rendering environment. The deprecated `windowDestination` closure is ignored; there is no separate window preference forwarding.

Presentation-scoped modifiers follow native SwiftUI rules. Departure leaves toolbar decisions to the system and does not copy window preferences or install device-specific overrides.

On UIKit, fade covers animate only opacity and complete native dismissal after the visible exit. Initial destination layout and toolbar placement do not inherit the fade animation; animations started by the destination remain available. On macOS, covers use native sheet presentation. Native presentation lifetime, source identity, and the shared transition coordinator remain independent of global availability.

Next: [Unwinding](unwinding.md) · [Sample app](../SampleApp/README.md)
