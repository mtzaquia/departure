# Global routes and dismissal protection

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
    .dismissalProtection()
  }
} destinations: {
  CheckoutFeature.destination
  SecondFactorFeature.destination
  PasscodeFeature.destination
  PasscodeFeature.helpDestination
}
```

`GlobalMap` accepts `Sheet`, `Cover`, and reusable `ModalRouteMap` values. Their children use ordinary declarations and feature maps. Global groups are accepted only in `RootRouteMap`; consumers need no extra presentation attachments. A destination creating a navigation stack still follows the usual `.routing()` placement rule.

Global requests use the same `await router.present(...)` API as local navigation. They preserve the current flow instead of crawling back to the global declaration's root. A single 2FA declaration can serve Checkout and Settings at different times; each presentation has its own route instance and state.

An equal global already in the foreground ancestry is reused and its unprotected descendants are removed. A new value for the current unprotected global replaces that occurrence in its existing slot. If reuse or replacement would remove an active protected route, the request presents a fresh global above it instead.

Global route types cannot also be declared locally in the composed tree. Such collisions, duplicate global declarations, and conflicting destination builders report diagnostics and disable the ambiguous type. Registering a destination builder alone does not make a route global.

## Protect only the active destination

`.dismissalProtection()` is available on sheets and covers, including local declarations. It takes effect only while that exact route's `routePhase == .active`.

With active Passcode protection, Departure admits:

- Any route declared in `GlobalMap`.
- A presentation matched in Passcode's own definitions, such as its Help sheet.
- Explicit dismissal targeting the exact Passcode instance, including its captured `@UnwindRoute` action.

Unrelated presentations are rejected without crawlback or branch activation. Ancestor unwinds and resets that would remove active Passcode are also rejected. Blocked requests are not queued for unlock. Requests waiting for normal transition completion recheck current protection before proceeding.

Presenting an unprotected global, declared sheet, or pushed child makes Passcode inactive. Its modifier then imposes no restriction: ordinary crawlback, reset, or ancestor unwind may remove it. If it survives and becomes active again, protection resumes automatically. A second protected global is allowed above it and protects itself while active. Protection is not inherited by child routes or branch containers.

`routePhase` follows participating path endpoints, including concurrent branches. It does not mean keyboard focus, physical visibility, or one scene-wide selected view. The modifier uses that same phase calculation.

Interactive dismissal belongs to the destination implementation. Departure does not set `interactiveDismissDisabled` or reject native dismissal events. A passcode feature that must prevent swipe dismissal applies its own modifier:

```swift
NavigationStack {
  PasscodeView()
    .routing()
}
.interactiveDismissDisabled()
```

The same responsibility applies to any presenting ancestor whose dismissal would remove the protected flow. Departure reconciles the exact occurrence after native dismissal; `.dismissalProtection()` governs routing requests.

## Dismiss and continue a flow

Use the ordinary captured dismissal action; no global-removal operation is required:

```swift
RouteDestination(PasscodeRoute.self) { _, context in
  Button("Unlock") {
    Task { await context.unwindRoute() }
  }
}
```

Dismissal actions retain exact instance identity. An old callback cannot close a replacement route. Await dismissal before continuing from a surviving router, and retain ordinary typed unwind handlers to receive results from shared authentication flows.

For notifications or deep links, keep a `RootRouter`. `rootRouter.root` captures the permanent app root; `rootRouter.current` captures the foreground scope at access time. Both respect active protection, and either may request globals. A stored scoped router never retargets after its source leaves navigation.

## Inherit presentation configuration

Sheets, slide covers, and fade covers use the presenting SwiftUI hierarchy in the current window. Set shared environment values above `WithRouter` or at the intended presenting scope. `RouteContext.environment` reads the destination's actual rendering environment. There is no `windowDestination` closure or separate window preference forwarding.

Presentation-scoped modifiers follow native SwiftUI rules. For example, [`toolbarVerticalBehavior`](https://developer.apple.com/documentation/swiftui/view/toolbarverticalbehavior(_:)) resolves separately in a sheet or form. Departure leaves those decisions to the system and does not copy window preferences or install device-specific overrides.

On UIKit, fade covers animate only their opacity and complete native dismissal after the visible exit. Initial destination layout and toolbar placement do not inherit the fade animation; animations started by the destination remain available. On macOS, covers use native sheet presentation. Native presentation lifetime, source identity, and the shared transition coordinator remain independent of global availability.

Protection applies to Departure-managed navigation. Arbitrary app-owned or system presentation controllers remain governed by their native owners.

Next: [Unwinding](unwinding.md) · [Sample app](../SampleApp/README.md)
