# Navigation operations

Status: implemented and validated on `zaquia/predefined-route-maps` (2026-10-08).

## Behavioral contract

Each accepted transition owns its unwind plan, outgoing presentation projections, and any presentation that continues after removal. The routing owner retains all unfinished operations and one latest pending request. Coordination remains global across independent priority spaces.

Logical removal cuts the live tree's ownership edges immediately. Native teardown may finish later. Outgoing objects remain ineligible for routing and hooks throughout that interval. A live source may request a presentation, but its request waits until every active operation completes and rechecks its captured source before continuing. Superseding a pending request resumes its caller exactly once.

Exact live membership is checked on arrival. A removed source is dropped immediately and never occupies the latest request slot. While an operation is unfinished, a live covered source can enter that slot and supersede the previous request. Coverage is checked when execution resumes: removal of the higher space allows the lower request to proceed, while a root reset or partial unwind that keeps the higher space causes it to be dropped. Source membership is also rechecked, followed by the remaining resolution, declaration, equality, and priority rules at its retained resolution stage. A request resolved before waiting is not resolved again. With no active operation, coverage is checked immediately. Rejected unwinds create no operation. An accepted target that removes nothing has no native teardown to await; it cannot hold a new presentation for a dismissal animation.

For example, successful MFA dismisses its high-priority entry sheet and requests screen X through a surviving default-flow router. Acceptance of the sheet's removal immediately removes its space from the live tree. X waits in the latest request slot while the sheet animates out. After native teardown, X is evaluated with default priority active and can proceed. The outgoing MFA router is inactive; it cannot stand in for the surviving default-flow source.

Different operations can overlap, including owner removal of covered high priority while critical priority is also removed. Each outgoing native stack retains its own projections until its operation releases them. Completion of one operation cannot clear another's projections. For an identical presentation key, the most recent active operation supplies the outgoing projection; live projections still take precedence.

Native and explicit unwinds enter matching handlers before committing the logical change. This includes explicit whole-space removal. The operation starts before notification, so a handler's presentation waits for unwind completion and rechecks its captured source and coverage afterward. Lookup follows the surviving local ancestry, then surviving lower spaces in descending priority. Covered scopes can receive notification; conflicting handlers stop fallback. The unwind does not await asynchronous handler completion. Native binding write-back without a matching handler can still commit synchronously; when a handler matches, commit follows notification. Equality stopping, branch targeting, top-space command gates, and exact instance protection remain unchanged. These notification and queue rules were accepted in the behavioral audit on 2026-10-08 and supersede the original native after-commit timing and admission-time coverage check.

Removal required by a presentation does not notify unwind handlers. Ancestor crawlback, equality reuse, and local or elevated replacement commit their structural changes and wait for teardown through the same operation coordinator, without handler delivery. This distinction between dismissal requests and presentation cleanup was accepted in audit E6 and supersedes the earlier notification on reuse and elevated replacement; snapshot and completion policies are unchanged.

An append that removes a modal preserves nested pushed bindings until that modal leaves. It then releases those projections before waiting for remaining pushed hosts, allowing their teardown to finish. Supersession prevents the old append from continuing. Cancellation after commit completes outgoing teardown without inserting the cancelled destination.

Branch activation can leave an accepted presentation awaiting its selected host. That same operation retains the presentation anchor after native completion, with its completed unwind plan released. This branch wait does not keep global navigation busy. A surviving branch host's readiness can also resume an already accepted presentation while outgoing native scopes finish, preserving the existing inline-replacement behavior. The operation still owns its outgoing plan and completion. Inserting the destination consumes its presentation once; completion cannot insert it again. This continuation is distinct from a new navigation request entering the global queue.

Cancellation while an append awaits outgoing teardown removes that exact operation from the latest presentation slot. A subsequent host refresh cannot revive the cancelled continuation. Native cleanup continues without a separate cancellation flag or lifetime ledger.

The iOS 17 staged replacement still removes pushed children before replacing their enclosing selection. It uses an operation to own that preparation and its completion. The accepted surviving presentation host remains the continuation anchor even if preparation removes the requesting child. New requests from the removed child remain inactive.

The synthetic transparent presentation base remains installed without animation before an elevated entry animates. This pass does not change its native presentation behavior or environment forwarding.

## Implementation

`NavigationOperation` owns an explicit stage: preparing an unwind or a presentation, committed teardown with or without a following presentation, awaiting a branch host, or finished. A stage determines whether a plan and/or a typed presentation exists, so they cannot be mutated independently. Committing consumes the prepared stage once; repeated commit cannot reapply an old plan. Supersession discards only the old continuation while retaining committed teardown and outgoing projections. `RouterEngine.navigationOperations` is the canonical collection of unfinished operations. Navigation readiness derives from this collection rather than a separate token registry. Completion clears the operation's projections and moves it to awaiting-host or finished, removes it from the collection, and drains the latest queued request only when that collection is empty.

The latest request slot distinguishes a request awaiting global readiness from an operation awaiting presentation continuation or branch installation. It references the operation directly; no separate append record duplicates its resolved route target or blocking scopes. Taking or cancelling a pending presentation uses one identity-checked operation. Queued requests retain their captured origin and resolution stage, so a resolved route is not resolved again after a wait.

A queued request owns its execution task after leaving the slot. Cancellation from its original caller reaches that task throughout resolution and presentation, while cancellation of the operation that released the queue does not cancel the unrelated request. Completion releases the execution and consumes the request's continuation exactly once. Request object identity replaces the former request UUID and cancellation lookup.

A single `ResolvedRouteTarget` flows from declaration lookup through planning and insertion. It retains the matched space and declaring/presenting scopes; paths and positions derive from those scope identities. The declaring owner can differ from the presenting scope for branch declarations and active-branch lookups. This distinction remains necessary for cleanup and branch selection. Attachment matches, presentation-anchor categories, location wrappers, and route-path translation helpers are removed. Lookup order, branch discovery, equality and unwind boundaries are unchanged; specification 8 remains an investigation rather than an adopted lookup policy.

Destination readiness uses one scope-bound wait for installation and physical teardown. Host completion is checked synchronously after the canonical host record changes, so short-lived transitions are not missed. Pending waits are weakly observed by their scope; the wait owns its continuation. Installation for an action retry also observes eligibility derived from the actual top space and ancestry. Removal, coverage, or cancellation ends that wait and releases a never-installed retry. No membership ledger, recursive cancellation cascade, or lifecycle flags are introduced. Committed physical teardown deliberately ignores caller cancellation and retains the global pause until native exit.

Outgoing projection lookup reads active operations by exact host and presentation kind. Observation follows the operation collection and each operation's projection changes. Native host lifecycle and physical bookkeeping remain canonical in the existing scope model.

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
