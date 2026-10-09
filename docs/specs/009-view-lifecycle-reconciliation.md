# View lifecycle and model reconciliation

Status: investigation and proposed direction, 2026-10-09. No runtime redesign is accepted or implemented by this document.

The investigation compares the main-branch sheet fix at `9276ee9f8e83daaf93c9790e30e2bf491881265a` with the map rewrite at `4128228`. Existing uncommitted work in the shared checkout is preserved. Runtime experiments use isolated copies.

## What the sheet fix establishes

The main fix combines three changes:

- The sheet presenter moves from a zero-size background onto primary content.
- A view-owned `SheetPresentationState` distinguishes requested dismissal from the still-rendered destination. It retains that destination until native dismissal completes and admits its successor afterward.
- Native writes and completion callbacks carry the exiting destination's identity. An older presentation cannot clear its successor. Reading retained state during `body` also prevents a first-presentation content closure from capturing an empty destination.

These are separate concerns. A green test of the combined fix does not isolate which change prevents a particular keyboard failure. Retaining outgoing content and rejecting stale native events are required behaviors; the opportunity is to implement those behaviors once at the presentation boundary.

## What the rewrite already improves

Definitions no longer depend on registration or view lifetime. Destination instances have stable identity. The [binding projection](../../Sources/Departure/Router/SwiftUI/Router+Presentation.swift) captures an expected instance and checks it before accepting native write-back. [Navigation operations](../../Sources/Departure/Router/NavigationOperation.swift) retain outgoing projections, and presentation replacement waits for removed mounted scopes before proceeding. The main fix's successor protection therefore has substantial equivalents already.

The rewrite still uses [zero-size background slots](../../Sources/Departure/Modifiers/View+RoutePresentationStyleModifiers.swift) for ordinary sheets and slide covers. Immutable definitions remove the old need to dynamically install declarations, but effective presentation-host ownership can still change. Placement remains worth investigating; copying the main fix wholesale would add another lifetime state machine before establishing which behavior is missing.

## Findings

### Physical teardown still has logical authority

[Host detachment](../../Sources/Departure/Router/Router+Navigation.swift) validates the lifecycle identity, completes physical waits, and can directly remove a live elevated space through `clearElevatedSpaceIfNeeded`. That last path calls `applyUnwindPlan` directly instead of the shared navigation-operation and unwind-notification entry path.

This is a confirmed code path, not a reproduced keyboard failure. It makes a leaf bridge's teardown a second authority for navigation removal. A bridge replacement or host disappearance has to be interpreted as either transient registration churn or actual presentation dismissal. Identity checks and deferred teardown protect same-turn replacements, but the distinction remains inferred from lifecycle.

An elevated root's actual dismissal must continue to dismantle its whole space, including while covered. A redesign should obtain that fact from the owning presentation adapter, with exact occurrence identity, and use the common unwind semantics. Removing this fallback requires proving all native and owner-teardown paths remain covered.

### Completion is inferred from destination teardown

[Unwind completion](../../Sources/Departure/Router/Router+Navigation.swift) waits for removed scopes' `isInstalledInView` to become false. Ordinary native sheets have no completion callback wired to the operation coordinator. The property records an accepted host registration, rather than the native transition's state.

This works in the bounded probes described below: native `onDismiss` preceded host detachment and `unwind()` return. Those results do not establish a universal ordering across sheet, cover, push, branch-switch, scene teardown, and supported OS versions. The existing iOS 17 watchdog itself shows that bridge teardown is not an infallible completion signal.

Modal completion should be acknowledged by its adapter's native completion event. Pushes still require their own tested completion mechanism because `navigationDestination` has no equivalent sheet `onDismiss` callback. Host teardown remains a fallback for destruction of the presenting owner, rather than the ordinary meaning of modal completion.

### Presentation lifetime is implemented several times

The current implementations include:

| Adapter | Native lifetime representation |
| --- | --- |
| Ordinary sheet / slide cover | Direct optional-item binding plus destination bridge teardown. |
| Default fade cover | Retained snapshot, visibility/dismissal flags, task IDs, and animation-duration sleeps. |
| Elevated window | Presented ID, pending snapshot, window-dismissal flag, and UIKit completion. |
| Elevated system sheet / slide cover | Separate `@State isPresented` started after base installation. |
| UIKit cross-dissolve presenter | Another presented ID, pending snapshot, hosting controller, and native dismissal handling. |

See [native styles](../../Sources/Departure/Modifiers/NativePresentationStyleModifier.swift), [fade presentation](../../Sources/Departure/Modifiers/CoverFadePresentationStyleModifier.swift), [elevated presentation](../../Sources/Departure/Views/ElevatedPriorityHost.swift), and [window ownership](../../Sources/Departure/UIKit/ElevatedPriorityPresentationWindowBridge.swift).

Actual native presentation can outlive membership in the logical tree, so some retained adapter state is necessary. It cannot be derived exclusively from X/Y/Z membership. However, occurrence validation, retaining the outgoing destination, accepting dismissal once, and acknowledging completion are common responsibilities. They should have one contract and common implementation where native semantics permit it.

### Scope mounting and presenter availability are different facts

`RouteScope.isInstalledInView` remains true through window disconnection until accepted terminal teardown. Ignoring transient window removal protects tab switches and scene transitions. Consequently, that property cannot also prove that the selected branch's native presenter is ready to present a sheet.

The current branch-selection turn and mount waits remain meaningful. A smaller bridge API should report host availability separately from terminal host destruction, and recheck presentation readiness from the actual selected host and native container. It must not turn a temporary loss of availability into an unwind or clear inactive branch history.

### Wiring can be consolidated without changing navigation behavior

[`RouteView`](../../Sources/Departure/Views/RouteView.swift), [branch routing](../../Sources/Departure/Modifiers/View+Routes.swift), and [root registration](../../Sources/Departure/Views/WithRouter.swift) repeat managed-scope attachment event handling. Routing and hooks then install additional bridges and largely repeat attachment refresh and teardown.

One managed-scope binding can own environment installation and the canonical native anchor. Typed routing/hook attachments can share refresh, identity validation, ownership gating, and deferred terminal cleanup. Arbitrary consumer modifiers can still need their own local attachment points; the goal is common handling, not pretending every modifier lives at one physical view.

The ownership gate remains necessary: an ordinary consumer-authored SwiftUI sheet inherits environment values but must not become another presentation or hook owner for its presenting Departure scope. Broad environment capture also has a purpose for contextual builders and detached forwarding. Narrow its update costs where possible without freezing consumer values or changing the forwarding contract.

### Captured-data refresh is coupled to window attachment

Routing and hook modifiers refresh their attachment payload only for installation or an update whose view is still in a window. Both ignore `updated(isInstalledInWindow: false)`. An already-installed attachment also preserves its existing registration during pending ownership without applying the refreshed payload.

The responder probe observed continuing branch registration refreshes, but no registration refresh during the sampled root-sheet typing interval, in both pre-fix main and the rewrite. Native focus remained held during that interval. This does not prove why root refresh pauses or establish a stale-environment bug; it prevents claiming that the root probe exercised registration reevaluation when its counter says otherwise.

The redesign should separate refreshing captured environment/handler data from admitting a new attachment and from native presentation readiness. Investigate refreshing an already-authorized exact attachment while its native anchor is temporarily unavailable. Preserve the unmanaged-sheet gate and live-membership rules; do not authorize a never-validated attachment merely because it inherited a scope.

## Proposed direction

Keep the existing definition map, live X/Y/Z topology, and global navigation coordinator. Redesign the boundary around three existing facts:

1. The model supplies the desired presentation and decides navigation authority from live membership.
2. A stable presentation host owns the actual rendered occurrence, including its outgoing lifetime after removal from the model.
3. Native adapters report an occurrence-specific dismissal request and completion. Generic representable teardown ends registration; destruction of a native presentation owner resolves its outstanding presentations explicitly.

Use a small common lifetime representation such as idle, showing an occurrence, and dismissing that occurrence. Derive its rendered destination and native presented flag. Keep the desired route in the model and pending navigation in the existing coordinator. Do not add a second navigation graph, a global mount ledger, or another command queue.

Move ordinary modal modifiers onto stable primary content if comparative reproduction and coexistence tests justify it. Keep push hosting conditional on push capability, so a scope that only presents a modal never requires a navigation stack. A root-elevated transparent base must still be installed immediately without animation, followed by the entry's native animation.

Unify lifetime machinery before unifying style-specific rendering. Native slide, custom fade, passthrough sizing, push replacement, and iOS 17 behavior have different requirements. A single generic presenter that changes those requirements would not be a simplification preserving behavior.

## Validation and remaining proof

The first four public-routing probes from the main fix, adapted to the map API, passed on an iPhone 17 Pro simulator running iOS 26.5: root and branch focus/typing/reopening, branch swipe dismissal/reopening, and root sheet replacement followed by unwind. Two instrumented root/branch cases observed `nativeDismissed -> hostDetached -> unwindReturned`.

The original root/branch focus probes also passed against pre-fix main. Thus the original keyboard instability has not been causally reproduced by those checks on this simulator. Later show/hide-notification and custom-environment expectations failed in plain SwiftUI as well as Departure. They are not evidence of a Departure regression and do not prove software-keyboard behavior when a hardware keyboard is used.

Focus proof must use the actual native responder and editing transitions, route/destination identity, and retained typed content. Controlled parent/environment and form-layout updates should exercise reevaluation independently of keyboard visibility. Deliberate focus resignation must be distinguished from unexpected resignation. The native probe must first prove it observes the actual mounted field in a plain SwiftUI control.

The refined probe uses `UITextField` editing notifications, a weak reference to the actual field, `isFirstResponder`, and object identity. Repeated form-layout updates run independently of keyboard notifications, while a source-environment counter requests parent updates. It verifies no additional editing end/begin transitions or native-field replacement during typing, the expected end/begin sequence for deliberate Done and Save, stable destination state, and a fresh destination after reopening. All five responder comparisons passed: plain SwiftUI, pre-fix main root/branch, and rewrite root/branch. The root registration-refresh assertion exposed the paused refresh described above, rather than focus loss; root focus and reopening passed when checked separately from that assumption.

Before implementing the boundary redesign, retain regressions for first presentation, focus through updates, native and programmatic dismissal, successor isolation, outgoing nested stacks, tab reveal/mounting, covered-space removal and notification, owner destruction, ordinary SwiftUI sheet coexistence, and the existing iOS 17 native behavior. Run focused checks during development and the full UI matrix at the resulting checkpoint.

Investigation logs: `/tmp/departure-lifecycle-baseline.log`, `/tmp/departure-lifecycle-ordering-corrected.log`, and `/tmp/departure-lifecycle-legacy-baseline.log`. Native responder results are in `/tmp/departure-lifecycle-legacy-native-responder.log` (plain SwiftUI and pre-fix branch passed), `/tmp/departure-lifecycle-rewrite-native-responder.log` (rewrite branch passed), `/tmp/departure-lifecycle-legacy-root-responder.log`, and `/tmp/departure-lifecycle-rewrite-root-responder.log` (both roots passed). The earlier root-refresh assertion failures in the first two logs are characterized above. Probe refinements and their failed assumptions are retained in `/tmp/departure-lifecycle-*-keyboard*.log` and `/tmp/departure-lifecycle-*-responder*.log`. Isolated source locations are recorded in `/tmp/departure-lifecycle-audit-path.txt` and `/tmp/departure-lifecycle-legacy-path.txt`.

These are Debug simulator checks on iOS 26.5. They do not reproduce the original affected device/composition or constitute the full UI matrix. No production implementation was changed by this investigation; only this audit document is added to the shared checkout.
