# Global maps

Status: implemented in the working tree. Updated 2026-11-07 to remove dismissal protection. This contract replaces the high/critical spaces and detached hosts described by [specification 5](005-independent-priority-spaces.md).

## Root-declared availability

A root-only `GlobalMap` contains multiple sheet and cover declarations. Its entries are available throughout the routing owner without repeated declarations or destination-specific attachments. Domain values conform to `Route`; there is no separate global-route protocol.

```swift
let routes = RootRouteMap {
    Cover(HomeRoute.self) { homeRoutes }
    GlobalMap {
        Sheet(SecondFactorRoute.self)
        Cover(PasscodeRoute.self, transition: .fade) {
            Sheet(PasscodeHelpRoute.self)
        }
    }
} destinations: {
    homeDestination
    secondFactorDestination
    passcodeDestination
    passcodeHelpDestination
}
```

The global map contributes declarations to one root-owned catalog. It does not create a runtime destination, another navigation tree, or a shared presented flow. Each accepted request creates or reuses an ordinary route occurrence. Children retain the full local declaration language, including pushes, branches, and reusable feature maps.

The builder accepts only `Sheet`, `Cover`, and `ModalRouteMap` at the global level. Each type accepts one global declaration and cannot also be declared locally in the composed tree. Diagnose collisions and disable the ambiguous type. Destination contributions still form one shared catalog.

## Resolve and present above the foreground

A global request uses the catalog but anchors presentation above the foreground flow. It does not crawl back to the catalog's root, select another tab, or discard the invoking pushes merely to find the declaration. Any live source can request a global; a removed source remains invalid.

Equal globals in foreground ancestry follow ordinary equality reuse: retain the matched occurrence and remove its descendants. A new value for the currently presented global replaces its existing presentation slot. A different global presents above the foreground.

For example, `Home → Checkout sheet → Details push` can present 2FA above Checkout while retaining Details. Dismissal returns to that flow. The same declaration can later present above Settings without implying a singleton challenge or shared view state.

Local requests retain ordinary scoped lookup. A covered caller does not borrow declarations from a foreground global. A global's own router can request its declared local children.

## Consumer-owned policy

`dismissalProtection()` and its declaration/runtime metadata have been removed. Departure does not block routing requests, actions, branch activation, ancestor unwinds, or resets based on the current route's phase. Consumers implement whichever navigation and dismissal rules their app needs.

Any live scope can issue commands while covered. Route resolution can reject forward requests, action interceptors can apply app policy, and feature controls can decide whether to send navigation or dismissal commands. `routePhase` describes participating path endpoints; it is not command authority or a dismissal barrier.

Native gesture policy also belongs to the destination implementation, including any presenting ancestor whose dismissal would remove the flow. A consumer's `interactiveDismissDisabled` modifier does not block router commands. Native binding write-back and owner callbacks reconcile the exact occurrence being dismissed, with ordinary before-commit notifications and stale-instance checks.

Retain source-lifetime, cancellation, declaration-conflict, host-readiness, and native-completion checks. These protect routing consistency, not an application dismissal policy. Requests waiting for an operation or native host recheck source and declaration eligibility before continuing. There is no unlock queue or covered-request policy.

## One tree and one window

The routing owner retains one immutable tree. Captured targets hold presenting and declaring scopes; delayed insertion checks live membership. Native presentation binds directly to its scope and style, retaining only the exact `PresentedRoute` while SwiftUI renders its ordinary `RouteView`.

Global sheets and covers use the existing SwiftUI modal adapters in the same window. UIKit fade covers use `fullScreenCover`, a clear presentation background, and opacity-scoped animation. Native lifetime, outgoing occurrences, instance checks, fade completion, push-host placement, and the iOS 17 push workaround remain necessary.

The elevated window bridge and fade presenter, pass-through windows/controllers, cached source environments, cached destination-view wrapper, and detached customization have been removed. So have high/critical priority spaces and space removal operations. `RootRouter.root` is the permanent external entry point; `current` captures the foreground scope.

For 3.1.0 source compatibility, `Compatibility/LegacyPriority.swift` retains the old public surface with deprecation warnings. `HighPriority` and `CriticalPriority` alias `GlobalMap`; `RoutePriority` retains its inert values, `RoutePresentation.priority` always returns `.default`, and `RootRouter.default` returns `current`. The old space-dismissal methods emit unconditional runtime warnings and return `false` without changing navigation. The `WithRouter(..., windowDestination:)` overload delegates to the ordinary host and ignores its customizer without storing or evaluating it. These shims do not restore priority policy or detached presentation.

Sheet compact adaptation is declaration metadata and native presentation preference. It changes neither the route tree nor the declared `.sheet` style.

## Sample and verification

The global-routes lab demonstrates shared 2FA, a fade passcode screen, declared children, ordinary covered-root navigation, ancestor crawlback, retained input, window identity, and inherited configuration. The sample owns gesture restrictions for Passcode and its confirmation sheet. It does not claim the router enforces a lock policy.

Package regressions cover global availability, equal reuse and current-value replacement, local/global conflicts, branch selection, covered-source actions and stored invocations, ancestor unwinds/reset, suspended requests, native callbacks, and removed-source rejection. Native UI tests cover global flows, ordinary navigation away from Passcode, child return, consumer-controlled confirmation, fade dismissal, and retained state.

Validated on 2026-11-07:

- 407 macOS package tests and 395 scene-backed iOS 17 tests passed.
- All seven global-route UI tests passed on iPad.
- Native interaction checks passed on i18P with iOS 27.2: fade Passcode, shared 2FA, confirmation dismissal, and covered-root navigation removing Passcode. Window identity and inherited configuration remained correct.
- Swift package and SampleApp Release builds passed.
- Markdown links, code fences, obsolete-symbol scans, and `git diff --check` passed.
