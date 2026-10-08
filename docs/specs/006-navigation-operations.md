# Navigation operations

Status: implemented and validated on `zaquia/predefined-route-maps` (2026-10-08).

## Behavioral contract

Each accepted transition owns its unwind plan, outgoing presentation projections, and any presentation that continues after removal. The routing owner retains all unfinished operations and one latest pending request. Coordination remains global across independent priority spaces.

Logical removal cuts the live tree's ownership edges immediately. Native teardown may finish later. Outgoing objects remain ineligible for routing and hooks throughout that interval. A live source may request a presentation, but its request waits until every active operation completes and rechecks its captured source before continuing. Superseding a pending request resumes its caller exactly once.

Exact live membership is checked on arrival. A removed source is dropped immediately and never occupies the latest request slot. While an operation is unfinished, a live covered source can enter that slot and supersede the previous request. Coverage is checked when execution resumes: removal of the higher space allows the lower request to proceed, while a root reset or partial unwind that keeps the higher space causes it to be dropped. Source membership is also rechecked, followed by the remaining resolution, declaration, equality, and priority rules at its retained resolution stage. A request resolved before waiting is not resolved again. With no active operation, coverage is checked immediately. Rejected unwinds create no operation. An accepted target that removes nothing has no native teardown to await; it cannot hold a new presentation for a dismissal animation.

For example, successful MFA dismisses its high-priority entry sheet and requests screen X through a surviving default-flow router. Acceptance of the sheet's removal immediately removes its space from the live tree. X waits in the latest request slot while the sheet animates out. After native teardown, X is evaluated with default priority active and can proceed. The outgoing MFA router is inactive; it cannot stand in for the surviving default-flow source.

Different operations can overlap, including owner removal of covered high priority while critical priority is also removed. Each outgoing native stack retains its own projections until its operation releases them. Completion of one operation cannot clear another's projections. For an identical presentation key, the most recent active operation supplies the outgoing projection; live projections still take precedence.

Explicit unwinds and native dismissal write-back share this entry path. An eligible unwind can begin while a presentation is waiting, including after that caller has been woken but before it resumes. Native write-back must reconcile a change SwiftUI is already making; it cannot wait behind a presentation. Logical commits run on the main actor, while native teardown can overlap. The global presentation barrier waits for all unfinished operations, and an awakened caller waits again if necessary. This preserves one unwind path without a separate FIFO command queue or native-event bypass policy.

Native and explicit unwinds enter matching handlers before committing the logical change. This includes explicit whole-space removal. The operation starts before notification, so a handler's presentation waits for unwind completion and rechecks its captured source and coverage afterward. Lookup follows the surviving local ancestry, then surviving lower spaces in descending priority. Covered scopes can receive notification; conflicting handlers stop fallback. The unwind does not await asynchronous handler completion. Native binding write-back without a matching handler can still commit synchronously; when a handler matches, commit follows notification. Equality stopping, branch targeting, top-space command gates, and exact instance protection remain unchanged. These notification and queue rules were accepted in the behavioral audit on 2026-10-08 and supersede the original native after-commit timing and admission-time coverage check.

Removal required by a presentation does not notify unwind handlers. Ancestor crawlback, equality reuse, and local or elevated replacement commit their structural changes and wait for teardown through the same operation coordinator, without handler delivery. This distinction between dismissal requests and presentation cleanup was accepted in audit E6 and supersedes the earlier notification on reuse and elevated replacement; snapshot and completion policies are unchanged.

An append that removes a modal preserves nested pushed bindings until that modal leaves. It then releases those projections before waiting for remaining pushed hosts, allowing their teardown to finish. Supersession prevents the old append from continuing. Cancellation after commit completes outgoing teardown without inserting the cancelled destination.

Branch activation can leave an accepted presentation awaiting its selected host. That same operation retains the presentation anchor after native completion, with its completed unwind plan released. This branch wait does not keep global navigation busy. A surviving branch host's readiness can also resume an already accepted presentation while outgoing native scopes finish, preserving the existing inline-replacement behavior. The operation still owns its outgoing plan and completion. Inserting the destination consumes its presentation once; completion cannot insert it again. This continuation is distinct from a new navigation request entering the global queue.

Cancellation while an append awaits outgoing teardown removes that exact operation from the latest presentation slot. A subsequent host refresh cannot revive the cancelled continuation. Native cleanup continues without a separate cancellation flag or lifetime ledger.

The iOS 17 staged replacement still removes pushed children before replacing their enclosing selection. It uses an operation to own that preparation and its completion. The accepted surviving presentation host remains the continuation anchor even if preparation removes the requesting child. New requests from the removed child remain inactive.

The synthetic transparent presentation base remains installed without animation before an elevated entry animates. This pass does not change its native presentation behavior or environment forwarding.

## Implementation

`NavigationOperation` owns an explicit stage: preparing an unwind or a presentation, committed teardown with or without a following presentation, awaiting a branch host, or finished. A stage determines whether a plan and/or a typed presentation exists, so they cannot be mutated independently. Committing consumes the prepared stage once; repeated commit cannot reapply an old plan. Supersession discards only the old continuation while retaining committed teardown and outgoing projections. `RouterEngine.navigationOperations` is the canonical collection of operations awaiting teardown. Navigation readiness derives from this collection rather than a separate token registry. Teardown completion clears the operation's projections and moves it to awaiting-host or finished, removes it from the collection, and wakes the latest queued request only when that collection is empty.

An unwind plan is constructed directly from retained scopes and spaces to remove. A retained scope names the owning X continuation to cut; a root or branch root is an ordinary scope anchor. The plan normalizes multiple anchors on one path to the shallowest scope, drops cuts covered by an ancestor or whole-space removal, and captures outgoing paths before mutation. Root reset supplies the space root, active branch roots, and the predecessors of modals in surviving inactive branches. Presentation cleanup supplies its presenting/declaring scopes or the exact equivalent destination. There is no path-position enum, trim wrapper, recursive unwind request tree, or separate presentation-transition enum.

The latest request slot distinguishes a request awaiting global readiness from an operation awaiting presentation continuation or branch installation. It references the operation directly; no separate append record duplicates its resolved route target or blocking scopes. Taking or cancelling a pending presentation uses one identity-checked operation. A queued request contains its route and a readiness continuation; its captured origin and resolution stage remain in the original caller's suspended function, so a resolved route is not resolved again after a wait.

Completing the last active operation wakes the latest waiting caller without executing or awaiting that presentation. The original caller claims its turn and continues in its own task, preserving cancellation and task-local context throughout resolution and presentation. A wake-up consumes only the readiness continuation; the request remains in the slot until its caller claims it. A newer eligible presentation can supersede an awakened request before it resumes. A covered or removed source cannot steal that ready slot. If another operation begins first, the same caller waits again. Identity checks prevent a superseded or cancelled caller from clearing a newer request. No queued execution task, cancellation relay, or copied resolution/origin fields are needed.

A single `ResolvedRouteTarget` flows from declaration lookup through planning and insertion. It retains the matched space and declaring/presenting scopes; paths derive from those scope identities. The declaring owner can differ from the presenting scope for branch declarations and active-branch lookups. This distinction remains necessary for cleanup and branch selection. Attachment matches, presentation-anchor categories, location wrappers, and route-path translation helpers are removed. Lookup order, branch discovery, equality and unwind boundaries are unchanged; specification 8 remains an investigation rather than an adopted lookup policy.

Destination readiness uses one scope-bound wait for installation and physical teardown. Host completion is checked synchronously after the canonical host record changes, so short-lived transitions are not missed. Pending waits are weakly observed by their scope; the wait owns its continuation. Installation for an action retry also observes eligibility derived from the actual top space and ancestry. Removal, coverage, or cancellation ends that wait and releases a never-installed retry. No membership ledger, recursive cancellation cascade, or lifecycle flags are introduced. Committed physical teardown deliberately ignores caller cancellation and retains the global pause until native exit.

Outgoing presentation lookup reads active operations by exact host and presentation kind. A binding value contains its exact destination scope and captured source environment; declaration and path remain canonical on the scope. Live membership and top-space eligibility determine whether native write-back may dismiss it, without a copied liveness flag. Snapshot classification uses the captured plan's removed scopes and path boundaries to retain departing bindings and suppress inner push animations. Observation follows the operation collection and its outgoing values. Native host lifecycle and physical bookkeeping remain canonical in the existing scope model.

Removed structures and paths:

- `NavigationTransaction` and its active token set.
- `AppliedTransition` and the separate removed-scope/snapshot-ID pair.
- Global `UnwindPresentationSnapshot`, snapshot IDs, install/clear matching, and snapshot handoff.
- `PendingRoute.Append`, duplicated blocking scopes, and the second append-deferral path. Route resolution already re-enters the global readiness gate before presenting.
- The outgoing record's redundant strong host reference; the operation's plan retains the outgoing subtree for native completion.

Production Swift source decreases from 8,185 to 8,097 lines: 88 fewer lines including the new operation type and request cancellation ownership. No public API is added.

## Regression evidence

New tests use `RootRouter`, `WithRouter`, and map declarations to create high and critical entry sheets, each containing two pushed destinations. They remove both spaces through the public owner API, verify both outgoing stacks, complete native exits in either order, and verify that the queued default presentation waits for both operations. A second test cancels a replacement after logical removal and verifies cleanup without insertion, followed by successful new navigation.

The same tests were run against an isolated copy of commit `f419419`, adapting only the internal coordination assertions. Both tests failed there: overlapping removals lost outgoing push bindings, and cancellation still inserted the replacement. The new implementation passes both tests without weakening their behavioral assertions.

Additional public-routing regressions verify cancellation after a queued request starts resolving and independence from a cancelled earlier unwind. Both fail against the isolated committed version: the queued request respectively ignores its own cancellation or inherits cancellation from the earlier operation. They pass with request-owned execution. The existing resolution-readiness test still verifies that waiting never resolves the route twice.

Native validation caught an overly strict branch-readiness guard introduced during this refactor: replacing from a pushed child left the compact split column empty. The unchanged UI test failed both in the full run and in isolation. A lifecycle test reproduces the surviving host's refresh; it passes on the committed version and fails with that guard. Restoring host-driven continuation preserves the existing behavior, while the operation keeps cleanup ownership. The same test verifies that cancellation prevents a refreshed host from inserting the destination. No native assertion was relaxed.

## Validation

| Check | Final result |
| --- | --- |
| macOS package suite | 313 tests in 22 suites passed. |
| iOS 27 package suite | All 308 tests passed. |
| iOS 17.5 package suite | All 308 tests passed. |
| Full iPhone/iOS 27 SampleApp UI suite | 39 passed, with the two expected iPad-only skips. |
| iPad/iOS 27 UI cases | Both passed, completing all 41 UI cases across iPhone and iPad. |
| iPhone/iOS 17.5 native regressions | All five passed: native Back/re-push, replacement from a child, outgoing sheet-stack retention, elevated-root reset/removal followed by default presentation, and owner removal of covered high while critical remains visible. |
| Mounted macOS presentations | Five tests covering six cases passed, including both elevated fade priorities. |

All checks used unchanged production, package-test, sample, and UI-test source. The full iPhone run was repeated after correcting the branch-readiness guard; its replacement assertions and every other native assertion remain unchanged. The combined implementation preserves the hook-composition and live-membership changes from the earlier pass.

Final XcodeBuildMCP result bundles in the Departure workspace are `test_sim_2026-10-08T10-01-36-841Z_pid93773_81299fbf.xcresult` (full iPhone), `test_sim_2026-10-08T10-28-05-199Z_pid96810_93190c31.xcresult` (iPad), `test_sim_2026-10-08T10-30-39-393Z_pid99147_7bcc0023.xcresult` (iOS 27 package), `test_sim_2026-10-08T10-31-28-038Z_pid99879_8602a30c.xcresult` (iOS 17.5 package), and `test_sim_2026-10-08T10-32-16-376Z_pid517_63098fd7.xcresult` (older-system native regressions). Local package and mounted results are recorded in `/tmp/departure-operations-macos-final2.log` and `/tmp/departure-operations-hosted-macos-final2.log`.

## Canonical target and readiness follow-up (2026-10-08)

The five accepted simplifications are implemented: branch concurrency comes from compiled definitions; declaration lookup produces one resolved target; installation and teardown share scope-bound readiness; operations have explicit stages; and effective presentation ownership cannot depend on mount order. The scope's two strong continuation queues are replaced by one collection of weak pending waits. Host facts and live eligibility remain canonical in the existing model.

The final package run passed **301 tests in 18 affected suites**, including the preserved hook changes, branch lookup and equality, concurrent spaces and outgoing snapshots, latest-request buffering, cancellation, action interception after installation, and iOS 17 preparation. New regressions cover conflicting presentation owners in either detachment order, automatic-owner ambiguity, removal and coverage before installation, cancelled installation, brief attach/detach transitions, and releasing an action retry for a never-installed removed destination.

An older covered-request test awaited a buffered presentation before releasing its outgoing host, preventing its own unwind from finishing. Its ordering now starts that presentation independently, verifies buffering, completes teardown, and verifies that the request is dropped because the higher space remains. No command admission rule was weakened.

Three existing iOS 27 UI tests passed for action routing, nested modal teardown, and retaining two pushed destinations during sheet removal. Two final iOS 17.5 cases passed for concurrent split replacement and outgoing sheet-stack retention. The sample's dismissal and nested-modal roots each had duplicate explicit `.routing()` declarations; their enclosing declarations were removed to comply with single-owner hosting. Native assertions remain unchanged. This is focused validation; the complete UI matrix was not repeated.

Evidence: `/tmp/departure-canonical-final.log`, `/tmp/departure-canonical-ui-final.log`, and `/tmp/departure-canonical-ios17.log`. XcodeBuildMCP bundles are `test_sim_2026-10-08T14-22-37-782Z_pid39134_639b05de.xcresult` (iOS 27) and `test_sim_2026-10-08T14-27-35-341Z_pid39893_bcf495ad.xcresult` (iOS 17.5).

## Continuous request completion (2026-10-08)

The accepted presentation keeps its original caller through deferred branch insertion. `NavigationOperation` retains the exact inserted destination in its stage, including while outgoing teardown remains unfinished. Teardown completion can release the global navigation gate while that same operation still awaits its branch host. Insertion, supersession, or cancellation completes the waiting caller once. A scheduled branch refresh belongs to that exact operation; it cannot consume a newer request's continuation.

Internal request completion returns the exact inserted or reused `RouteScope`, including an elevated space's root. Rejected, superseded, and cancelled attempts return no destination. Action rerouting uses that scope directly and preserves its installation wait before invoking destination interceptors. It no longer infers the retry destination from a space's selected foreground scope or the original branch owner. Local and elevated equivalent-route reuse share one scope-returning implementation.

`Router.present` retains its public signature. Its return boundary includes deferred insertion into routing state; it does not wait for the destination view to mount or finish animating. Existing host callbacks, selection-update staging, outgoing snapshots, modal teardown waits, iOS 17 replacement preparation, and global latest-request buffering remain necessary and are preserved. This change does not adopt a new discovery policy or remove SwiftUI timing workarounds.

Enclosing branch selections and the destination container's selection are checked for ownership conflicts and compatible binding types before any enclosing selection is written. An invalid inner binding therefore cannot partially reveal its outer tab. The actual selection writes and final branch insertion retain their existing staging boundaries.

Public-map regression scenarios fail against the preceding commit for partial ancestor reveal and action retry through the original branch rather than the reached ancestor destination. Both pass after this change. Completion tests also verify exact scope identity for branch, equality, elevated, and buffered requests, plus single consumption of an awaiting-host continuation.

Focused validation covers 200 distinct package tests in nine affected suites: 198 passed together, followed by the ten completion/operation tests including two added contract regressions. All three iOS 27 native cases passed for branch crawl and tab-to-sheet staging, modal arbitration from a pushed branch, and action routing. Both iOS 17.5 native cases passed for branch crawl and concurrent split replacement. Native UI assertions are unchanged; the full matrix was not repeated. Older package assertions expecting a completed `present` call to leave insertion pending now reflect the documented completion boundary.

Evidence: `/tmp/departure-request-focused-final.log`, `/tmp/departure-request-completion-contract.log`, `/tmp/departure-request-baseline.log`, `/tmp/departure-request-native-27.log`, and `/tmp/departure-request-native-17.log`. XcodeBuildMCP bundles are `test_sim_2026-10-08T15-01-13-817Z_pid44880_c2e60058.xcresult` (iOS 27) and `test_sim_2026-10-08T15-05-04-698Z_pid45696_1f0af7a6.xcresult` (iOS 17.5).

## Resume the original caller (2026-10-08)

Unwind completion now wakes the buffered presentation's original caller instead of creating and awaiting another execution task. The suspended caller retains its origin and resolution stage, preserves its own cancellation and task-local values, and rechecks membership and priority coverage before proceeding. An unwind awaits its own teardown independently of the following presentation's resolution or insertion. The execution task, its cancellation relay, and copied request origin/stage fields are removed. Native staging and branch-host waits remain unchanged.

Two public-map regressions fail against the preceding implementation: buffered resolution inherits the completing unwind's task-local context, and the unwind cannot return while its following route is still resolving. Both pass with caller-owned continuation. Four further regressions cover supersession after wake-up, cancellation before claiming the turn, another unwind beginning before the caller resumes, and a covered attempt being unable to steal an awakened top-space request.

The focused package run passed **232 tests in 10 suites**. Both iOS 27 native checks passed for elevated-root reset/removal followed by default presentation and native/explicit dismissal handler timing. The iOS 17.5 concurrent split replacement check also passed. The first iOS 27 runner failed to load Foundation before test bootstrap; rerunning on a freshly booted simulator passed without production or test changes. The complete UI matrix was not repeated.

Evidence: `/tmp/departure-caller-wake-baseline.log`, `/tmp/departure-caller-wake-focused.log`, `/tmp/departure-caller-wake-native-27-fresh-simulator.log`, and `/tmp/departure-caller-wake-native-17.log`. XcodeBuildMCP bundles are `test_sim_2026-10-08T15-41-14-866Z_pid50778_d99a4c6c.xcresult` (iOS 27) and `test_sim_2026-10-08T15-40-29-563Z_pid50601_ccebeadd.xcresult` (iOS 17.5).

## Scope anchors and direct unwind plans (2026-10-08)

Unwind plans now retain exact scope anchors and remove exact space instances. Roots and branch roots use the same anchor representation as destinations. `RoutePath.Position`, `RoutePathTrim`, `UnwindResolution`, the recursive `UnwindPlanRequest`, and `PresentationTransition` are removed. Explicit targets resolve once to a scope; equality reuse returns that scope directly. Native dismissal and the iOS 17 adapter use the same plan constructor. The adapter derives its path from its captured scope instead of storing another path reference.

Plan construction merges anchors on the same path, drops descendant cuts covered by an ancestor or whole-space removal, and captures outgoing paths before any owning edge is cut. Detached branch subtrees remain intact for outgoing snapshots and ARC. Resetting to a branched root retains inactive pushes; resetting past a branch container removes all of its branches. Handler timing, native staging, cancellation, independent spaces, and the global latest-presentation barrier remain unchanged. Explicit and native unwinds continue to share their immediate entry path.

Production Swift source decreases from 8,351 lines at `fbcb45f` to 8,025 lines: **326 fewer lines**. The new public-map regression verifies that redundant branch anchors collapse to one ancestor cut while outgoing snapshots retain both branch paths and their destinations.

The replacement suite had two stale assertions expecting an awaited `present` to leave branch insertion pending. Both failures reproduce against `fbcb45f`, before this refactor. The corrected test requires insertion before return and verifies that later host refresh cannot insert the destination twice. All 15 replacement tests pass with the correction against both the preceding production code and this implementation.

Focused validation passed **280 package tests in 16 suites**, plus a Release build. Three unchanged iOS 27 UI cases passed for outgoing sheet-stack retention, unwind targets across a branch container, and elevated-root reset/removal followed by default presentation. Two unchanged iOS 17.5 cases passed for native Back/re-push and concurrent split targeting with local dismissal. The complete UI matrix was not repeated.

Evidence: `/tmp/departure-scope-anchors-focused-final.log`, `/tmp/departure-scope-anchors-release.log`, `/tmp/departure-scope-anchors-replace-baseline.log`, `/tmp/departure-scope-anchors-replace-baseline-corrected.log`, `/tmp/departure-scope-anchors-native-27.log`, and `/tmp/departure-scope-anchors-native-17.log`. XcodeBuildMCP bundles are `test_sim_2026-10-08T16-04-56-881Z_pid55215_47144b82.xcresult` (iOS 27) and `test_sim_2026-10-08T16-08-21-190Z_pid56064_2b2024fc.xcresult` (iOS 17.5).

## Scope-based presentation values and direct admission (2026-10-08)

`PresentedRoute` now carries only its destination scope and captured source environment. The scope's immutable presentation metadata supplies the declaration, style, and priority, including after its origin or space leaves the tree. Its canonical owning path supplies local dismissal's retained anchor. `ResolvedRoutePresentation`, its duplicate path, and its `isLive` flag are removed. Outgoing values preserve rendering and environment capture; exact live membership and top-space eligibility determine command authority. Native binding setters still compare the originally captured destination instance before accepting write-back.

Outgoing classification uses one removed-scope set and one ancestry predicate. Each captured path supplies the first departing destination and whether its owner also leaves. This replaces the separate departing-host and outermost-push scans plus their intermediate identity sets. Modal-contained bindings retain their existing teardown lifetime; a push-only unwind animates only the outermost departing push. The iOS 17 staging adapter, synthetic window base, deferred branch insertion, and global presentation barrier are unchanged.

Presentation admission now proceeds directly from declaration lookup through source equality, the priority gate, and append or elevated-space reuse/replacement. `RouteTransitionPlan`, `PriorityDecision`, and their translation helpers are removed. Missing and conflicting declarations, blocked spaces, source equality, branch reveal, and elevated equality retain their previous ordering and diagnostics. This adds no public API or discovery policy.

Production Swift source decreases from 8,025 lines at `a4c584c` to 7,904 lines: **121 fewer lines**. Public-map regressions verify stale native bindings against a new instance with the same route ID in all three priorities, plus outgoing branch bindings retaining their captured environment while their dismissal write-back lacks routing authority. The affected package run passed **314 tests in 20 suites**, and the Release build passed.

Three unchanged iOS 27 UI cases passed for retaining two pushes during native sheet dismissal, high-window replacement and continuation, and critical overlay/replacement above the high flow. Both unchanged iOS 17.5 cases passed for native Back/re-push and concurrent split targeting with local dismissal. The separately mounted macOS suite passed all five tests, including both elevated fade priorities. The complete UI matrix was not repeated.

Evidence: `/tmp/departure-presentations-focused-final.log`, `/tmp/departure-presentations-release.log`, `/tmp/departure-presentations-mounted-macos.log`, `/tmp/departure-presentations-native-27.log`, and `/tmp/departure-presentations-native-17.log`. XcodeBuildMCP bundles are `test_sim_2026-10-08T16-27-56-565Z_pid58372_5ea2c8d0.xcresult` (iOS 27) and `test_sim_2026-10-08T16-31-18-308Z_pid59174_c7fb9cfd.xcresult` (iOS 17.5).

## Full UI checkpoint (2026-10-08)

The full UI matrix was run against library checkpoint `8ace2ee`. The first iPhone run passed 38 cases, failed one, and skipped the two expected iPad-only cases. The failure reproduced in isolation with the checkpoint unchanged: pushing login detail could not find its destination view.

`LoginRoute` builds a `RoutedNavigationStack`, which already binds its root. `LoginView` also declared an explicit `.routing()`, creating two presentation owners in the same scope and correctly disabling local presentation under the single-owner rule. Removing that redundant sample modifier fixes the configuration. The failing case then passed in isolation, followed by a complete iPhone rerun. Library source and UI assertions remain unchanged.

| Final check | Result |
| --- | --- |
| Full iPhone/iOS 27 UI suite | 39 passed, zero failures, two expected iPad-only skips. |
| iPad/iOS 27 UI cases | Both passed, zero failures or skips. |
| iPhone/iOS 17.5 native regressions | All five passed, zero failures or skips. |

Together the iPhone and iPad runs exercise all 41 UI cases. Older-system coverage verifies native Back/re-push, replacement without a Back entry and with child-navigation cleanup, outgoing sheet-stack retention, elevated-root reset/removal followed by default presentation, and owner removal of covered high while critical remains visible. The full suite was not repeated on iOS 17.5. No source changes followed the corrected sample's successful isolated check and final matrix.

Evidence: `/tmp/departure-checkpoint-full-iphone-27.log` (initial full run), `/tmp/departure-checkpoint-high-flow-baseline.log` (isolated reproduction), `/tmp/departure-checkpoint-high-flow-fixed.log` (isolated fix), `/tmp/departure-checkpoint-full-iphone-27-final.log` (full rerun), `/tmp/departure-checkpoint-ipad-27.log`, and `/tmp/departure-checkpoint-native-17.log`.

Final XcodeBuildMCP result bundles are `test_sim_2026-10-08T17-02-49-496Z_pid63442_a39386f0.xcresult` (full iPhone), `test_sim_2026-10-08T17-26-10-698Z_pid66279_65ee2477.xcresult` (iPad), and `test_sim_2026-10-08T17-28-13-002Z_pid66757_29975caf.xcresult` (iOS 17.5 regressions).

## Scope-owned unwind delivery on 2026-10-08

Each source `RouteScope` owns its unwind-handler entry tasks, keyed by the receiving scope ID. This preserves deduplication for overlapping explicit and native unwinds while removing the engine's global delivery history, composite source/target keys, weak-source wrapper, and stale-source cleanup. Delivery state follows the source instance's lifetime, including when outgoing views retain that instance. Distinct instances of the same domain route never share delivery history.

The callback still enters before commit. Overlapping unwinds await the same entry boundary without awaiting the asynchronous handler body. Handler presentations still wait for global teardown and recheck source membership and priority coverage. Handler lookup, payload delivery, and presentation-crawlback exclusions remain unchanged. The entry task does not retain its source scope, so a suspended callback does not prolong the removed scope's lifetime.

Production Swift decreases from 7,759 lines at `81ba05a` to 7,742 lines: **17 fewer lines**. The regression that injected a stale global-history key is replaced with public routing that presents and unwinds two instances of the same route while retaining the first outgoing instance. A new lifetime regression verifies deallocation while a handler is suspended in default, high, and critical spaces. Existing overlap and timing assertions remain unchanged.

Validation: **75 package tests in 8 affected suites passed** on the final code, covering unwind hooks, cross-priority notification and follow-ups, presentation-crawlback exclusions, hook composition and eligibility, action hooks, operation overlap, request completion, and outgoing snapshot policy. The final run has no compiler warnings. The full UI matrix was not repeated for this bookkeeping-only pass. Evidence: `/tmp/departure-scope-unwind-focused-final.log`.
