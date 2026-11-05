# Global maps and dismissal protection

Status: implemented and verified in the working tree, 2026-11-05. This contract replaces the high/critical spaces and detached hosts described by [specification 5](005-independent-priority-spaces.md). Verification results are recorded below.

## Requirements established in this discussion

- Declare a root-only `GlobalMap` containing multiple route declarations. Its entries are available throughout the routing owner without repeated declarations or destination-specific attachments.
- Reuse a 2FA destination from several flows without giving it artificial presentation priority.
- Apply `.dismissalProtection()` directly to the declaration requiring protection, such as the passcode cover. Protection is effective only while that exact route's `routePhase == .active`.
- While protection is effective, block unrelated navigation requests. Allow requests for global routes and presentations matching a declaration belonging to the presented protected global route.
- Presenting an unprotected destination above a protected route makes the underlying route inactive, so its protection stops applying. Ordinary navigation may then remove it incidentally.
- There is no separate covered-request policy, deferred-until-unlock queue, or protected priority tier.
- Use the existing window and ordinary SwiftUI modal adapters for globals and fade covers, without detached destination configuration.

## Separate availability from dismissal protection

Global availability answers **where a declaration can be found**. Dismissal protection restricts navigation only while that declaration's route instance is active. No additional policy controls requests from underneath.

This revises the original passcode requirement: explicit dismissal is required while the lock itself is active. Protection is suspended when an admitted destination takes over. It resumes automatically if the same lock instance becomes active again.

Keep domain values conforming to `Route`. Make `GlobalMap` a root-only group of route declarations, consistent with the existing separation between route data, placement, and `RouteDestination`. Apply `.dismissalProtection()` to a `Sheet` or `Cover` declaration inside that group. Neither feature requires a new domain-route protocol or a wrapper around each route.

An illustrative declaration is:

```swift
let routes = RootRouteMap {
    Cover(HomeRoute.self) { homeRoutes }

    GlobalMap {
        Sheet(SecondFactorRoute.self)
        Cover(PasscodeRoute.self, transition: .fade) {
            Sheet(PasscodeHelpRoute.self)
        }
        .dismissalProtection()
    }
} destinations: {
    homeDestination
    secondFactorDestination
    passcodeDestination
    passcodeHelpDestination
}
```

`GlobalMap` contributes all of its entries to the global catalog. It does not create a runtime destination, a modal lane, or one shared presented flow. Each accepted route request creates or reuses its own destination instance according to the routing rules.

The declarations preserve existing `Sheet`/`Cover` child maps. The 2FA declaration is ordinary; Passcode has dismissal protection; Help does not inherit it. The modifier must preserve the declaration's style, child definitions, and builder eligibility. Applying it more than once should have the same effect as applying it once.

Dismissal protection is declaration metadata independent of global availability. Its contract also applies to local modal declarations; placing a protected declaration in `GlobalMap` adds global availability. It does not establish another route kind or priority tier.

Accept only sheets and covers inside `GlobalMap`, including their modified declarations. A globally available push still depends on a suitable navigation stack and cannot offer the same presentation guarantee. Enforce root placement and modal-only construction through the builders, rather than accepting invalid combinations and failing at runtime. The modifier must not accidentally let a push into the modal-only builder.

## Resolve a global declaration without crawling back

Compile global declarations into a root-owned catalog separate from local scope definitions. Continue using the existing single destination catalog. Declaring a global at the root must not make the root its local navigation anchor.

For a global request, resolve the declaration from that catalog, then present in the foreground's deepest modal lane. Use a stable routing host for that lane; the requesting scope supplies request identity, not necessarily the physical presenter. Do not select a different tab, discard pushes, or dismiss an existing modal just to reach the declaration.

Equal globals in foreground ancestry follow ordinary equality reuse, and a new value for the current unprotected global replaces its existing presentation slot. Before choosing that anchor, check the resulting removal plan against effective protection. If reuse or replacement would remove an active protected instance, fall back to a fresh occurrence above the foreground. This preserves the global admission exception without bypassing active dismissal protection.

For example, `Home → Checkout sheet → Details push` can present 2FA above Checkout while retaining Details. Successful dismissal returns to that exact flow. The same declaration can present above Settings later. It does not imply a singleton view or a single shared authentication challenge.

Conflict rule: one global declaration per route type, and no local declaration of that same type anywhere in the composed tree. Diagnose conflicts and disable the ambiguous type. Otherwise contextual shadowing could silently bypass a global declaration's dismissal protection.

Any live source may request a declared global with ordinary `router.present(...)`, including a source underneath an active protected route. Global availability does not revive a removed source. System-driven requests use `rootRouter.root.present(...)`, capturing the permanent application root. `rootRouter.current` instead captures the foreground scope. Both respect the same admission rules.

## Derive effective protection from route phase

Keep the existing tree, paths, and modal lanes. Effective protection is computed from declaration metadata and the current navigation state:

```text
effectiveProtection(route) =
    route.declaration.hasDismissalProtection
    && route.phase == .active
```

The declaration retains its modifier while inactive. There is no sticky protected state, explicit rearming step, or inherited protection on descendants. Reuse the same model-derived phase exposed through the environment; do not use appearance, animation completion, or a delayed environment update as a second authority.

| Navigation state | Effective protection |
| --- | --- |
| Passcode is active and has the modifier | Passcode protects itself. |
| An unprotected global 2FA sheet is presented above Passcode | Passcode becomes inactive; neither route has effective protection. |
| An unprotected Help sheet declared by Passcode is presented | Passcode becomes inactive; Help does not inherit protection. |
| A protected global is presented above Passcode | Passcode becomes inactive; the new global protects itself while active. |
| An unprotected pushed child becomes active | The parent is inactive; only the child's own modifier could give it protection. |
| The upper destination is dismissed and the same Passcode instance becomes active | Passcode protection resumes automatically. |
| Ordinary crawlback removes inactive Passcode while an unprotected destination is active | Allow under ordinary routing rules; the inactive modifier does not preserve it. |

`RoutePhase.active` currently describes participating path endpoints and may apply to several concurrent branch endpoints. It does not mean keyboard focus or one universally selected view. Preserve that meaning and test protection against the same phase calculation. In particular, a route owning active branch roots can itself be inactive; its modifier must not become protection for the whole branch container.

## Admit requests while a protected route is active

For a live requester, the presentation exception is:

```text
allow presentation when:
    no effective protection applies
    OR the requested route has a global declaration
    OR the presented protected route has a matching local declaration
```

The local exception means a declaration in that protected route's own routing definitions, for both global and local protected modals. Finding an unrelated declaration in the covered app's ancestry is not sufficient. Match the declaration before selecting a branch or removing navigation, and preserve ordinary ambiguity and missing-destination diagnostics.

| Request with Passcode active and protected | Result |
| --- | --- |
| Present globally declared 2FA | Allow above Passcode even though 2FA has no protection. |
| Present another protected global | Allow above Passcode; protection follows the resulting phase change. No handoff API or priority comparison is needed. |
| Present Help declared by Passcode | Allow; Help's own declaration determines protection after it becomes active. |
| Present an app route declared only below Passcode | Block without crawlback, branch changes, or removal. |
| Use a stored live lower router to request a global | Allow the global exception; present over the foreground, not at the lower source's anchor. |
| Use a stored live lower router to request a route declared by Passcode | Allow through the presented global's matching declaration without revealing the covered source. |
| Use a removed router to request any route | Reject under the existing source-lifetime rule. |
| Implicitly remove active Passcode through unwind, reset, replacement, or container removal | Block unless it is a deliberate dismissal of that exact active instance. |
| Explicitly dismiss that exact Passcode instance | Allow and await ordinary native dismissal completion. |

Once an admitted presentation makes Passcode inactive, its modifier imposes no remaining veto on presentation, equality reuse, ancestor unwind, reset, branch changes, or container removal. Apply ordinary rules and honor any other route currently active and protected. Do not retain a frozen subtree, reset-to-lock boundary, or special equal-lock behavior.

Explicit dismissal must remain tied to the intended instance. A stale callback must not dismiss its replacement. The existing captured `@UnwindRoute` and `RouteContext.unwindRoute` actions express that intent. No separate global dismissal operation is required.

Blocked requests are rejected, not retained for unlock. Existing admission and native-transition waits still apply. After resolution, rerouting, suspension, or host staging, recheck the final declaration, source lifetime, and current protection before committing. A request started before the lock appeared cannot bypass it; a resumed request must not be blocked by protection that is no longer effective. Check the pre-change state when admitting a request so a forbidden mutation cannot justify itself by first making the protected route inactive.

## Present in the existing window

The intended native shape is:

```text
Existing scene window
└─ App navigation
   └─ Checkout sheet and its pushed detail
      └─ Global passcode cover (inactive; protection suspended)
         └─ Global 2FA sheet (active; unprotected)
```

Departure should install the required modal adapters automatically at routing hosts, including scopes with no local modal declarations. Consumers should not add a host for each global. An allowed global must be able to present above the active protected route; there is no always-topmost critical lock tier.

While a protected route is active, prevent incidental teardown of its native presenting ancestry as well as its logical removal. Once it becomes inactive, release that restriction. Native and model behavior must agree with the phase-based rule rather than preserving a hidden lifetime barrier after another destination takes over.

Apple documents that dismissing a controller lower in a modal stack also dismisses the controllers above its child. See [`dismiss(animated:completion:)`](https://developer.apple.com/documentation/uikit/uiviewcontroller/dismiss(animated:completion:)). For an inactive protected route, such removal can be permitted by this contract. For an active protected route, the adapter must prevent unauthorized ancestor dismissal. A root-only SwiftUI overlay is not sufficient for drawing above a separately presented sheet.

Likewise, [`interactiveDismissDisabled(_:)`](https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:)) prevents interactive dismissal but not programmatic dismissal. Apply native dismissal restrictions consistently with effective protection and reconcile explicit native dismissal against the exact instance. Disappearance, scene inactivity, or destination-view teardown must not independently authorize removal of an active protected route. If native dismissal happens unexpectedly, retain the logical restriction and reconcile; recovery alone cannot prove that covered content was never exposed.

Global and fade destinations use the existing SwiftUI sheet/cover adapter. Departure no longer allocates an elevated `UIWindow` or constructs a separate hosting controller for them.

The guarantee is scoped to navigation managed by this `RootRouter` in its scene. For an unmanaged camera, importer, system alert, or app-owned modal, determine whether lock presentation must wait, dismiss that presentation through its owner, or use an integration point. Do not promise to cover every native or system surface without validating that contract. In particular, a native dismissal of an unmanaged presenting ancestor can remove the lock independently of Departure's mutation planner.

## Remove detached fade configuration

UIKit fade covers use `fullScreenCover`, a clear presentation background, and staged opacity in [the native modal modifier](../../Sources/Departure/Modifiers/NativePresentationStyleModifier.swift). The animation transaction is scoped to opacity, so native toolbar placement and initial destination bounds do not animate from their provisional layout. They build the ordinary destination directly, preserving the presenting hierarchy's environment. Admission, outgoing snapshots, instance checks, and delayed native teardown remain in place.

The elevated window bridge, elevated fade presenter, pass-through window/controllers, `WindowDestinationBuilder`, and `WithRouter(windowDestination:)` overload have been removed. So have `HighPriority`, `CriticalPriority`, `RoutePriority`, presentation priority metadata, and space removal operations. `RootRouter.root` replaces the external-entry role formerly served by `RootRouter.default`.

Keep the general modal lifetime adapter, native dismissal reconciliation, push-host placement safeguards, outgoing destination snapshots, and the single transition coordinator. These address native lifetime and sequencing even in one window. Inventory references before deleting any shared helper.

## Regression coverage

The table defines the model and native regression coverage required for this implementation. Package cases use public routing; native checks mount actual presentation hosts or drive the sample.

| Scenario | Evidence required |
| --- | --- |
| 2FA from a root, pushed detail, sheet, slide cover, and fade cover | Same root declaration works; the invoking flow and entered state survive dismissal. |
| One `GlobalMap` with ordinary and protected entries | Each entry is globally available; only the modified declaration gains dismissal protection. Modified entries preserve child maps and modal-only builder constraints. |
| `.dismissalProtection()` on a local modal and repeated on one declaration | Protection does not depend on global availability; repeated application is idempotent. |
| Lock over every supported managed presentation | Lock is fully visible and interactive; no extra window is created; keyboard and accessibility focus enter the lock. |
| Lock requested during interactive dismissal, presentation, or a background/foreground transition | Gate takes effect correctly, existing transitions complete safely, and no stale callback unlocks a replacement. |
| Active Passcode receives a global request from its own router and a live covered router | Both present the global above it without crawling back to the catalog root. |
| Active Passcode receives a declared child request and an unrelated app request | Child is admitted; unrelated request is rejected without partial changes or a deferred-until-unlock request. |
| Unprotected global, declared sheet, or pushed child becomes active above Passcode | Passcode becomes inactive and ordinary removal can include it. No inherited protection survives. |
| Upper destination is dismissed while Passcode remains live | Passcode becomes active and protection resumes. |
| A protected global is presented over another protected global | The request succeeds; only currently active instances enforce protection. |
| Equality reuse, ancestor unwind, reset, branch changes, and owning-container replacement | Active protection blocks incidental removal; inactive modifiers do not add special restrictions. |
| Concurrent branches and a global owning a branch container | Effective protection follows each scope's actual phase, without protecting an inactive parent. |
| Resolution reroutes, suspended requests, and host staging across phase changes | Final admission uses current phase and matched declaration, with source/cancellation checks preserved. |
| Explicit close, native `dismiss()`, swipe/keyboard dismissal, and unexpected host loss | Dismissal intent, phase, instance identity, and native lifetime agree. |
| Environment and shared appearance configuration in 2FA and fade lock | Custom environment values, toolbar behavior, orientation, safe areas, color scheme, and `RouteContext` agree without `windowDestination`. |
| Fade entrance, exit, immediate child push, and successor presentation | No slide, flash, premature teardown, or misplaced navigation destination; retain existing iOS 17 timing coverage. |
| Unmanaged modal or alert already visible | Establish the supported integration/ordering behavior before claiming the lock covers it. |
| iPad split branches and macOS | Modal coverage and phase agree across branches; presentation and dismissal behavior are documented without assuming UIKit equivalence. |

The sample now includes global 2FA, active Passcode protection, allowed global and local overlays suspending protection, a second protected global, and restoration on return. `GlobalRoutesTests` covers the visible flows, window identity, inherited configuration, and retained input.

## Verification

| Check | Result |
| --- | --- |
| macOS package and mounted presentation tests | 406 tests passed in 36 suites. |
| Scene-hosted package tests on iOS 17 | 392 tests passed. The fake-host fixture controls its own exit timing; production watchdog coverage remains separate. |
| Scene-hosted package tests on iPadOS 27.2 | 392 tests passed. |
| Final targeted iOS 27.2 sample UI run | 13 checks passed, covering the six global/protection flows, global replacement and retained nested stacks, alert dismissal, and destination context. The two former priority-specific nested-stack cases were identical after migration and have since been consolidated into one global case. |
| iOS 17 sample regressions | Nine applicable tests passed: six global/protection flows and three global replacement styles. |
| iPadOS 27.2 sample regressions | Eight applicable tests passed: six global/protection flows and two split-view cases. |
| Native automatic toolbar behavior on Duo | Catalog text fits; the lab opens and closes; Passcode → 2FA → Done restores protection; Unlock returns to the app. Window identity and inherited configuration agree. No device-specific toolbar policy is installed. |
| Repeated fade entrance on Duo | The reported toolbar movement and second-entrance resizing were reproduced. After scoping the animation to opacity, frame-by-frame native recordings of three consecutive entrances show a stable toolbar and full destination bounds throughout. |
| Fade lifecycle follow-up on iOS 17 | Four mounted tests passed, including repeated fade presentation, destination-owned animations, and waiting for the visible exit before teardown. |
| Release builds | Library and final sample app succeeded; final sample Debug build also succeeded. |

The earlier complete 74-case sample plan produced 66 passes, two platform skips, and six failures. Those failures exposed an outdated alert expectation and global reuse/replacement defects; all six affected cases passed in the final targeted run after correction. The complete plan was not rerun as one final batch. The older-system and iPad runs each skipped a device-specific test that has now been removed; their applicable cases all passed.

## Native ownership boundary

Protection governs Departure-managed navigation. Unmanaged native presentations, arbitrary programmatic dismissal by external controllers, and macOS window closure remain owned by their respective native controllers. No platform-wide interception or additional window is installed.
