# View lifecycle and model reconciliation

Status: accepted and implemented, 2026-10-09. The investigation below records the evidence and limits that led to the implementation.

The investigation compares the main-branch sheet fix at `9276ee9f8e83daaf93c9790e30e2bf491881265a` with the map rewrite at `4128228`. The initial investigation preserved concurrent work and ran experiments in isolated copies. The implementation follows the resulting audit on the map branch.

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

## Accepted direction

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

The boundary redesign must retain regressions for first presentation, focus through updates, native and programmatic dismissal, successor isolation, outgoing nested stacks, tab reveal/mounting, covered-space removal and notification, owner destruction, ordinary SwiftUI sheet coexistence, and the existing iOS 17 native behavior. Run focused checks during development and the full UI matrix at the resulting checkpoint.

Investigation logs: `/tmp/departure-lifecycle-baseline.log`, `/tmp/departure-lifecycle-ordering-corrected.log`, and `/tmp/departure-lifecycle-legacy-baseline.log`. Native responder results are in `/tmp/departure-lifecycle-legacy-native-responder.log` (plain SwiftUI and pre-fix branch passed), `/tmp/departure-lifecycle-rewrite-native-responder.log` (rewrite branch passed), `/tmp/departure-lifecycle-legacy-root-responder.log`, and `/tmp/departure-lifecycle-rewrite-root-responder.log` (both roots passed). The earlier root-refresh assertion failures in the first two logs are characterized above. Probe refinements and their failed assumptions are retained in `/tmp/departure-lifecycle-*-keyboard*.log` and `/tmp/departure-lifecycle-*-responder*.log`. Isolated source locations are recorded in `/tmp/departure-lifecycle-audit-path.txt` and `/tmp/departure-lifecycle-legacy-path.txt`.

These are Debug simulator checks on iOS 26.5. They do not reproduce the original affected device/composition or constitute the full UI matrix. The investigation itself changed no production implementation. The subsequent implementation is recorded below.


## Implementation

The live X/Y/Z model and global navigation coordinator remain authoritative for desired navigation and eligibility. `NativePresentationLifetime` owns one rendered occurrence at the adapter boundary. It distinguishes a prepared request, native admission, dismissal, and completion. Preparation is necessary because SwiftUI can coalesce a sheet request with its cancellation before creating any destination; that case has no native dismissal callback to await. Admission comes from destination creation in the lifecycle bridge, or installing the UIKit presentation owner. No animation-duration guess controls navigation completion.

An admitted occurrence remains retained until its native adapter acknowledges completion. Repeated synchronization does not rebuild the destination. A different desired route first dismisses the old occurrence, and the adapter reads the latest model value after completion. There is no pending route stored in a presenter. Exiting callbacks carry the occurrence identity, and a replaced native owner cannot remove the same still-live occurrence owned by its successor. A weak completed-occurrence reference prevents replay while an unwind notification enters before commit, without retaining the old scope or relying on memory-address uniqueness after deallocation.

Ordinary sheets and slide covers use the common lifetime with `onDismiss`. The default fade cover uses the same retained occurrence; opacity-animation completion requests native dismissal, and `onDismiss` acknowledges it. Its duration sleeps and separate pending/dismissal state machine are removed. The elevated UIKit cross-dissolve child renders one fixed occurrence and forwards completion to its owning window instead of maintaining its own successor queue.

The elevated window also owns the common lifetime. It installs its transparent base immediately inside `UIView.performWithoutAnimation`, then allows the modal to animate from that installed base. Dismissal retains the window and destination through UIKit's modal-dismissal completion. Only that completion hides the window and removes its root controller, inside `UIView.performWithoutAnimation`. It restores the previous key window only if the removed window was key, so removing covered high priority does not take key-window ownership away from critical priority.

Modal waits derive from the exact native lifetime, even if a destination bridge has already detached or remains retained afterward. Pushes retain their existing managed-host completion and iOS 17 adapter. Outgoing topology snapshots continue preserving nested stacks until their modal owners complete. No global mount ledger, navigation graph, or command queue is added.

Generic destination-host detachment now ends registration only. Native owner dismissal or destruction requests the common unwind operation for the exact live occurrence, including removal of a covered elevated root. Native and explicit unwind notifications retain their before-commit semantics. A stale outgoing occurrence cannot remove a successor space. Covered-space navigation remains blocked, and buffered follow-up presentations still wait for all operations and recheck coverage.

Managed root, branch, and destination bindings share host-event handling. Hook and routing attachments share event refresh and teardown handling. An exact already-authorized attachment refreshes consumer data while ownership is pending during window disconnection; a never-authorized attachment remains pending. A positively unmanaged attachment is removed and diagnosed. This preserves ordinary SwiftUI-sheet isolation and exact live-membership eligibility for hooks. Native presenter availability is derived separately from retained installation, preserving inactive histories while branch reveal waits for an available anchor.

Ordinary presentation slots remain in their existing locations. The investigation did not establish presenter placement as the original focus failure's cause. This pass unifies lifetime ownership and completion without adding a speculative hierarchy change. Focus probes are now retained in the SampleApp suite and use native editing transitions, a weak field reference, first-responder status, object identity, retained text, and repeated layout/environment updates. Software-keyboard visibility is not their focus signal.

## Implementation validation

The package checkpoint passed **393 tests in 30 suites**. The lifetime tests cover retained outgoing content, stale callbacks and replaced owners, native completion independent of bridge teardown, native destruction of a covered elevated root, buffered follow-up navigation, cancellation before native admission, ARC release, and dismissal completion arriving before the first unwind commits. Completion acknowledges an already-requested dismissal without starting another unwind operation.

The full SampleApp iPhone suite passed **44 tests on iOS 26.5**, with two iPad-only cases skipped. Both skipped cases then passed on an iPad simulator running iOS 27. The full run preceded the final weak-anchor distinction and completion deduplication; affected checks were rerun separately after those narrow refinements.

Native app-hosted UIKit tests on iOS 17.5 passed all ten ownership/availability checks, plus a parameterized high/critical window-lifetime test. The latter observes animation enablement at key-window insertion, holds an actual UIKit dismissal transition open, verifies the window and modal remain intact during that transition, and releases it to verify teardown with animation disabled. This establishes the window completion contract; visual animation quality is covered by the public-routing UI scenarios rather than this controlled renderer.

Mounted macOS checks passed all six test functions, including native modal dismissal completing the routing operation. The final production implementation also built in Release.

The first focused iOS 17.5 run passed eight navigation/dismissal cases, while two focus probes timed out waiting for twelve samples. Diagnostic counters showed one editing start, zero editing ends, the same native field still first responder, and only nine samples. The probe recreated its timer publisher during reevaluation. Its publisher now has stable view-state ownership; timeout diagnostics include the actual native counters. All six final iOS 17.5 checks passed: the five focus/replacement/cancellation cases and native dismissal/handler timing. Three final iOS 26.5 checks also passed: root/branch native focus and elevated replacement/continuation. These reruns used the final production implementation and corrected sampler.

The iOS 27 iPhone runner failed to launch because its Foundation runtime library/dyld cache was unavailable, before any test executed. The iOS 27 iPad runner worked. Neither that launch failure nor the probe's sampling timeout establishes a library regression. The original focus instability from main remains unreproduced on the affected device/composition; this pass improves ownership and completion contracts without claiming a causal reproduction of that bug.

The production Swift implementation has **117 fewer lines** than the starting checkpoint, including the common lifetime type. Tests and the retained SampleApp probe add coverage rather than production machinery.

Checkpoint logs: `/tmp/departure-lifetime-package-checkpoint.log`, `/tmp/departure-lifetime-full-ui.log`, `/tmp/departure-lifetime-ipad.log`, `/tmp/departure-window-lifetime.log`, `/tmp/departure-lifetime-macos-checkpoint.log`, `/tmp/departure-lifetime-release-current.log`, `/tmp/departure-lifetime-ios17-focus-final.log`, and `/tmp/departure-lifetime-final-focus-ui.log`.

## Shared unwind execution

The follow-up consolidation uses one `performPlannedUnwind` executor for explicit unwinds, whole-space removal, native dismissal, and completion of already-committed equality crawlback. It owns notification, pre-commit authorization, commit, presentation-completion waits, and coordinator release. Entry points still prepare their existing plans and notification scopes. Equality crawlback supplies no notifications; removing multiple spaces notifies their roots in descending priority order.

The existing authority distinctions are explicit inside the executor: a scoped command requires top-space membership and may be cancelled before commit; an owner command may remove covered spaces and may be cancelled before commit; a native owner completes an actual dismissal independently of coverage. Once an operation commits, cancellation cannot undo it or skip its completion wait. The executor derives that boundary from the existing operation stage, without another lifecycle flag or request queue.

Native write-back without a matched handler still commits synchronously in its calling stack. Its deferred task uses the same executor to await completion and release coordination. With a matched handler, the executor enters notification before commit and continues when the callback suspends, preserving buffered follow-up presentations and their later coverage checks. Two unused dismissal wrappers and absent-source handling were removed. Public API and navigation behavior are unchanged; this follow-up deletes **15 net production lines**.

Validation passed 91 tests in the affected hook, priority, lifetime, readiness, authority, compatibility, and execution suites, plus 153 tests in the router suites. The new execution tests exercise scoped/owner cancellation before and after commit, buffered continuation after cancelled committed removal, coordinator cleanup, and synchronous native write-back. Mounted macOS tests and the final execution tests passed together (eight test functions). Five focused native UI cases passed: iOS 26.5 native/explicit handler timing, elevated-root reset/removal/default continuation, and covered high-space removal; iOS 17.5 native Back/repush and priority-window replacement/continuation. The previous full UI checkpoint was not repeated for this bounded consolidation.

Follow-up logs: `/tmp/departure-unwind-executor-regressions.log`, `/tmp/departure-unwind-executor-router.log`, `/tmp/departure-unwind-executor-hosted.log`, `/tmp/departure-unwind-executor-ui26.log`, and `/tmp/departure-unwind-executor-ui17.log`.
