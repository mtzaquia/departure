# Push host placement

Automatic routing boundaries can wrap content that creates its own `NavigationStack`. Attaching `navigationDestination(item:)` to that outside boundary causes SwiftUI's misplaced-destination warning, even if an explicit `.routing()` inside the stack later takes ownership.

## Reproduction

Temporary lifecycle logging on the original implementation showed the automatic host entering the window, becoming the presentation owner, and building its push slot before the explicit host's `installedInWindow` event. The explicit host subsequently became the owner. Scope ownership priority was correct; the initial native slot placement was premature.

The console collector was checked with the placement gate temporarily bypassed. Its assertion failed with exactly one `com.apple.SwiftUI` warning for `Optional<PresentedRoute>`. Restoring the gate makes the same assertion pass. The collector reads `OSLogStore(scope: .currentProcessIdentifier)`; the simulator tool's default app-subsystem filter would miss SwiftUI's warning.

## Implementation

An automatic host starts without a push slot. After its native lifecycle anchor enters a window, a coalesced main-actor task checks public UIKit responder/controller containment. Only an anchor inside a navigation controller can install the automatic push slot. A stack below the anchor does not qualify. This applies equally to root, branch, pushed, sheet, and cover scopes; there is no modal-root exception.

The native check is the readiness condition. A main-actor hop alone would still depend on SwiftUI's scheduling of the stack's root controller. A descendant preference alone would not make an outside host usable in a stack with no explicit host. Automatic slots can become ready before any push is requested and remain installed through transient window detachment, avoiding pending-item-driven insertion/removal. AppKit keeps automatic hosting with deferred installation because it has no corresponding public navigation-controller containment API.

Explicit priority and conflict detection still use `RouteScope`'s existing host registry. Only the selected host receives presentation styles; an automatic host waiting for stack placement keeps its non-push styles and physical scope anchor. Removing an explicit host restores the automatic slot when its anchor is inside a stack. Existing iOS 17 `pushHostIdentity`, nil-write-back interception, and dismissal transaction handling are retained.

A push destination explicitly receives the router engine captured by its slot. This supports `NavigationStack { WithRouter { Root() } }`: SwiftUI can build the destination in the outer stack's environment, outside the environment supplied by `WithRouter`.

## Immediate child pushes on iOS 17

A pushed destination can request its own child from `.task` before the parent's native push animation finishes. The original eager-host implementation also loses this child on iOS 17. Installing a slot after only a main-actor hop does not establish native readiness.

On iOS 17, the automatic host now checks its containing controller's public transition coordinator. When an animated transition is in progress, it waits for that coordinator's completion before installing the slot, rechecking the current lifecycle identity and window. Existing slots remain installed. There is no fixed-duration delay, and the item binding, dismissal transactions, and existing nil-write-back workarounds remain unchanged. Requests still complete after routing state updates; this does not change `Router.present` into an animation-completion API.

The sample retains immediate-child regressions for a root stack and for sheet, slide-cover, and fade-cover stacks. Their destinations execute real router requests from `.task` and assert that the second pushed destination becomes visible with no misplaced-navigation warning.

## Root-stack trade-off

`WithRouter { NavigationStack { Root() } }` has no usable stack-side host. Departure leaves the outside push slot absent and emits an actionable warning when a push is requested. Add `.routing()` inside the stack:

```swift
WithRouter(routes: routes) {
    NavigationStack {
        Root().routing()
    }
}
```

No wrapper or extra stack is introduced: the application retains its path binding, native value destinations, and stack ownership. A pending push can be presented when a stack-side host is installed later; the sample includes this transition.

## Coverage

| Requirement | Sample proof |
| --- | --- |
| A: sheet/cover owns a stack | Sheet, slide cover, and fade cover with a bound path, native value destination, and explicit routing. |
| B: pushed destination has push children | The first pushed destination omits routing; push, unwind, and re-push its child. |
| C: root stack with explicit routing | `explicit` probe. |
| D: root stack without explicit routing | `missing` probe asserts the Departure diagnostic; `late` installs the missing host with a non-nil item. |
| E: router inside an outer stack | `outer` probe. |
| F: branch-owned stacks | `branch` probe and the existing tab/split suites. |
| G: plain modal with no push children | Plain sheet and plain cover probes. |
| Handover and a pending item | Remove an explicit host; install an explicit stack-side host after a push is pending. |

Package tests cover style gating, explicit priority, conflict detection, automatic restoration, stale nil write-backs across handover, and actual UIKit ancestry. `PushHostTests` attaches console output and asserts zero misplaced-navigation warnings in every supported layout.

## Validation setup

The native iOS suite runs all package tests in a temporary scene-backed test application with `DEPARTURE_RUN_HOSTED_UI_TESTS=1`. A standalone SwiftPM XCTest process has no `UIWindowScene`, so it cannot exercise the existing native-window tests. The temporary host leaves the repository's package and SampleApp project unchanged.

The full SampleApp runs also exposed two stale unwind expectations in `testBranchCrawlActivationAndStackPersistence` and `testDirectCoverCurrentUnwindAndProtectedSettingsRoute`. Both failures reproduce against unchanged `main`: `.nearestModal` dismisses the enclosing landing cover, while the tests expected its settings content to remain. The tests now use `.current` for a single pop and reopen the landing cover when continuing after `.nearestModal`. This is a test-flow correction; the unwind implementation is unchanged.

Verified locally with Xcode 27.2:

| Check | Result |
| --- | --- |
| Scene-backed package/native tests, iOS 17.5 | 478 passed, no failures or skips. |
| Scene-backed package/native tests, iOS 27.2 | 478 passed, no failures or skips. |
| Push-host UI regressions, iOS 17.5 | All 16 passed, including immediate child pushes from root, sheet, slide cover, and fade cover. |
| Push-host UI regressions, iOS 27.2 | All 16 passed. |
| Full SampleApp phone UI run, iOS 17.5 | 66 passed, two stale unwind expectations failed, two iPad-only cases skipped. |
| Full SampleApp phone UI run, iOS 27.2 | 66 passed, the same two stale unwind expectations failed, two iPad-only cases skipped. |
| Corrected unwind UI flows, iOS 17.5 and iOS 27.2 | Both passed on each runtime in targeted reruns. |
| iPad split-branch UI cases, iOS 27.2 | Both passed. |
| macOS package tests | 494 passed. |
| Release builds | iOS SampleApp and macOS package succeeded. |

The console collector's bypassed-gate positive control captured one misplaced SwiftUI navigation warning. Every push-host regression asserts zero such warnings and retains its complete process-log transcript as a test attachment. The `missing` scenario deliberately emits one Departure placement diagnostic instead; installing a stack-side explicit host later presents the pending push.

Each iOS result bundle contains 18 console captures across the 16 push-host tests (the branch test captures three stages). All 36 captures report zero SwiftUI navigation warnings and inspect nonempty process logs. Only the missing-host and late-install scenarios report a Departure placement diagnostic, one each per runtime.
