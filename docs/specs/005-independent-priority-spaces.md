# Independent priority spaces

Status: Implemented. Automated and functional native checks passed; animation-frame verification is limited by recording. The accepted rules below supersede the corresponding cross-priority behavior in specification 3.

## Accepted rules

Each priority has an independent navigation space. Creating a high or critical space makes the entry destination its navigation root, at X zero and Y zero. Its outer sheet or cover presents the space; it is not a modal transition within the space. There is no navigation ancestry into another priority.

An elevated presentation still needs a synthetic base in its detached window. Insert the window and its base immediately, without animation, then animate the actual sheet or cover from that installed base as a normal presentation. Removing that staging base would let the destination appear already presented or blink into place during its slide. Nonanimated base insertion must not suppress the destination's subsequent presentation animation.

The base is presentation infrastructure, not the destination targeted by navigation root reset, route lookup, hooks, or branch operations. The implementation may retain an internal base scope where the native presenter requires it; that does not make it an additional navigable X/Y position. Resetting a space keeps its entry destination and outer presentation visible. Dismissing the space tears down its destination and presentation base.

`unwind(to: .root)` resets navigation within the requesting space while keeping its root visible. It never dismisses that space or resets another priority. Dismissing an entire space is a separate operation.

Root reset preserves inactive branch pushes only when the space root itself owns that branch container. It clears participating branch navigation and modal presentations according to the retained root-unwind policy. Any branch container removed on the way to the root loses all of its branches, including inactive history. Dismissing the entire space discards all of its paths, including inactive branch history.

Branch lifetime follows container ownership, rather than a blanket inactive-path preservation rule. Disconnecting a container from the live tree disconnects every branch it owns. A retained outgoing container may still hold its old paths for presentation continuity, but those paths are outside live navigation. ARC releases that subtree after its outgoing owners finish; removing a container must not require recursively emptying its branches.

Calling `unwindRoute` from the root destination of a high or critical space dismisses that entire space. From a descendant it dismisses that destination as usual. The permanent normal root cannot be dismissed this way. The covered-space navigation gate still applies to this local unwind action.

Only the top space may originate navigation. Every other space is covered and rejects presentations, replacements, unwinds, root resets, and branch selection or activation. This includes requests to create or replace an equal-or-higher priority space: a covered normal space cannot open critical while high is on top. The lower space retains its navigation state while covered.

The source space determines eligibility, not the destination's priority or the scope that owns its declaration. A captured router remains bound to its source space; the normal root's router has no implicit owner privilege. Rejected requests are dropped rather than queued for later. Requests that suspend during resolution or readiness must still originate from the exact live top space when they commit; losing that eligibility prevents the navigation from committing.

An explicit owner-level dismissal can close an addressed space even when it is covered. This is deliberately separate from navigation originating in a space, and a covered scoped router cannot use it as a bypass. Closing high while critical exists leaves critical intact; closing critical reveals the highest remaining space. No source-space gate is needed for this explicit coordination operation.

Full dismissal removes the entire space from live navigation state: its root, every path, every modal lane, and all branch history. This remains distinct from resetting navigation to its root. Removal takes effect when dismissal commits, as in the existing implementation; the removed space does not remain as an empty root or a blocking closing state. The highest remaining space immediately becomes top and is eligible to navigate.

Outgoing snapshots may retain the removed destination views until native teardown completes. This retention exists only for presentation continuity and command completion; it does not retain a live space, grant eligibility to captured routers from it, or keep the remaining spaces covered. Eligible requests from a remaining space can still wait in the global transition pipeline for required outgoing completion and physical host readiness. Navigation eligibility and transition readiness are separate conditions.

Pending requests, navigation transactions, and outgoing snapshot coordination remain global under the routing owner. Independent space navigation state does not imply independent transition scheduling. One global coordinator must preserve ordered flows that remove a high-priority space and then present a normal-priority route, waiting for the necessary teardown and host readiness before starting the next presentation.

For that chain, commit high-space removal, finish the required outgoing presentation work, then present from the now-eligible normal space. The follow-up request targets a surviving source scope rather than the removed high destination. Ordinary requests from a covered normal space remain rejected; an ordered chain must sequence removal before attempting its normal navigation. Source identity, eligibility, cancellation, and supersession checks still apply when an accepted pending request resumes.

## Coordination rules

The routing owner coordinates space creation, replacement, dismissal, priority ordering, navigation eligibility, and global transition sequencing. Every space owns its navigation root, X continuations, Y modal lanes, and Z branches. Coordination does not establish a parent relationship between spaces. Global pending requests, transactions, and snapshot coordination use one transition pipeline; they are not duplicated into per-space state machines. Presentation bases retain only the native staging and readiness responsibilities needed to animate their destinations.

| Operation | Behavior |
| --- | --- |
| Present a locally declared destination | Require the requesting space to be top, then resolve and navigate within it using existing nearest-match and equality rules. |
| Present a mapped priority entry | Require the requesting space to be top, then ask the owner to create or replace that priority's space. The destination becomes the navigation root. Insert the detached window/base without animation before animating its outer presentation. Reject entry requests below the highest existing priority. |
| Present an equivalent entry root | Require the requesting space to be top, then reuse the existing root and apply its local root-reset policy. Only inactive branches owned by that retained root preserve history. Equality is checked against that space's entry root, not an equal local child. |
| Present a different entry at an existing priority | Require the requesting space to be top, then replace that entire space. Other priorities keep their state. |
| Unwind to an ancestor or ID | Require the requesting space to be top, then resolve only within it; there is no fallback to a lower-priority ancestor. |
| Unwind to the space root | Require the requesting space to be top, then retain the root and reset navigation in that space. Preserve inactive pushes only for the root's own branch container; remove every branch owned by a discarded container. |
| Invoke the root destination's unwind action | Require the requesting space to be top, then close its high or critical space. The permanent normal root cannot be closed this way. |
| Select or activate a branch | Require the owning space to be top. A rejected selection cannot alter its retained branch state. |
| Dismiss an entire space | Remove that space's root and all navigation it owns when dismissal commits, even when covered. Keep every other space intact and derive the top space from those that remain. |
| Chain high-space removal into normal navigation | Sequence removal and required native teardown before the normal presentation. Resolve the follow-up from a surviving normal scope once normal is eligible; recheck eligibility and readiness before committing it. |
| Complete native dismissal of the outer space presentation | Complete teardown of that exact outgoing instance. For an interactive dismissal, remove the matching live instance if still present. A stale callback cannot dismiss a replacement at the same priority. |

Local definition lookup, action interceptors, unwind handlers, and payload recipient lookup stop at the space root. A priority-entry catalog belongs to the routing owner and remains available for deliberate entry requests; consulting that catalog does not expose another space's local definitions or hooks. Closing a space does not implicitly deliver a payload to a lower space.

The top space is the highest-priority space present in logical navigation state, including accepted presentations before their native host mounts. Environment forwarding for detached hosts remains sourced from the owner as agreed in specification 1; environment forwarding does not imply navigation ancestry.

Blocking applies to all navigation mutations, including binding write-back and branch activation. It does not suppress unrelated background actions or application work; any navigation produced by an action still passes the same source-space gate. Physical host attachment, detachment, snapshot cleanup, and completion of an already committed transition remain possible while covered. Those lifecycle events cannot authorize a new navigation request or dismiss a replacement instance.

Unwind plans, outgoing snapshots, equal-route stopping, branch targeting, native readiness, cancellation, and stale-instance protection remain necessary. The owner coordinates their transitions globally over independent space state. Cross-space ancestry recovery, lower-space ID fallback, and implicit global root unwind can be removed. Synthetic presentation bases and global transition sequencing remain required.

## Required behavioral checks

- Opening a sheet-rooted high or critical space inserts its detached window/base without animation, then visibly animates the sheet from the installed base. The destination must not blink into an already-presented state. Base insertion must not disable its presentation animation.
- Resetting a sheet-rooted elevated space retains its entry destination and outer sheet; it does not unwind to the synthetic base. The same logical-root rule applies to cover-rooted spaces.
- An ordered flow removes high and then presents a normal route only after required outgoing teardown/readiness. A normal request attempted while high remains live is still rejected; a pending eligible request rechecks its exact source when the global transaction completes.
- Normal opens high. A captured normal router cannot push, unwind, switch branches, or open critical while high is top. High can open critical.
- Critical covers high. A captured high router cannot replace high, reuse its entry root, reset its paths, dismiss itself, or activate a branch.
- Removing critical immediately makes high top with its retained navigation state. Requests from high are eligible while critical's outgoing snapshot finishes native teardown; the global coordinator sequences their execution according to required outgoing completion and actual presentation-host readiness.
- Full dismissal removes the root and inactive branch history. Resetting a branched root preserves its own inactive pushes. Resetting past a descendant branch container removes all of that container's branches.
- A branched root has an active branch containing another branch container, and an inactive sibling with saved pushes. Root reset retains the sibling's pushes but removes every branch of the discarded nested container. Captured routers for those discarded branches remain inactive, including while outgoing objects are retained.
- A request begins in the top space and suspends. Another space becomes top before it commits. The suspended request is rejected without changing any path or branch selection.
- An explicit owner dismissal closes covered high while critical remains intact. A stale high presentation callback cannot close a replacement high instance.
- Covered spaces can finish previously committed native transitions and release outgoing snapshots without accepting new navigation.

Use ordinary public routing to establish these states. Model assertions must verify unchanged paths and branches after rejected requests; native checks must verify the visible result and dismissal timing.

The presentation-base animation and global sequencing requirements were reaffirmed on 2026-10-08. They supersede the proposal to remove the base or distribute transition machinery into the individual spaces.

## Public removal API

The owner handle and scope-bound navigation handle are distinct:

- `RootRouter` owns the routing container and is the optional explicit handle passed to `WithRouter`.
- `Router` is bound to one scope. It is supplied through the environment and `RouteContext.router`; it has no owner-level removal operation.
- `RootRouter.current` returns a `Router` bound to the current position in the top space at the time of access. External entry points use the same scoped navigation operations as views. Keeping that returned router captures its source identity rather than dynamically retargeting it after an asynchronous wait.

```swift
@State private var rootRouter = RootRouter()

WithRouter(routes: AppRoutes.root, router: rootRouter) {
    AppView()
}

// Ordinary external navigation captures a scope in the current top space.
await rootRouter.current.present(LoginRoute())

// Inside any destination in the top elevated space:
await context.router.dismissSpace()

// Explicit owner coordination, including covered spaces:
await rootRouter.dismissSpace(.high)
await rootRouter.dismissSpaces()
```

The signatures are:

```swift
extension Router {
    @discardableResult
    public func dismissSpace() async -> Bool
}

extension RootRouter {
    public var current: Router { get }

    @discardableResult
    public func dismissSpace(_ priority: RoutePriority) async -> Bool

    @discardableResult
    public func dismissSpaces() async -> Bool
}
```

| Call | Meaning |
| --- | --- |
| `router.unwind(to: .root)` | Reset the receiving space to its root. Preserve inactive pushes only for that retained root's own branches. Require the source space to be top. |
| `unwindRoute()` | Dismiss the receiving destination; at an elevated space root, remove the whole space. Require the source space to be top. |
| `router.dismissSpace()` | Remove the receiving high or critical space from any depth. Require that exact live source space to be top. |
| `rootRouter.dismissSpace(.high)` | Remove the high space present when the owner command is accepted, including when it is covered. Other spaces remain intact. |
| `rootRouter.dismissSpaces()` | Remove every elevated space present when the owner command is accepted in one logical commit. Keep normal navigation intact. |

The scoped call returns `false` for an inactive scope, a covered space, or the permanent normal space. The addressed owner call returns `false` for an absent priority or `.normal`. The plural call returns `false` when no elevated spaces exist. A successful call returns `true` after native exit and required snapshot cleanup, consistent with unwind completion. Logical removal and top-space eligibility change at commit, before that asynchronous completion.

Owner commands capture the addressed space instances when accepted. A replacement created during teardown is not part of the earlier command, including a plural dismissal. Captured routers from removed instances remain inactive. Cancellation before commit leaves navigation unchanged; cancellation after commit cannot resurrect a removed space.

Whole-space removal has no payload overload. Ordinary unwind payloads stay within their space; an explicit cross-space result mechanism remains a separate design question. `RouteContext` retains its existing four properties and uses `context.router.dismissSpace()` without adding another environment action.

This replaces the dual role of `Router()` as an unscoped owner and scoped handle. `RootRouter` references the same core owner; the public type distinction does not introduce another ledger, navigation model, or coordinator.

## Decisions still to agree

- Whether to retain an explicit owner-level reset of all spaces, separately from local root unwind.
- Whether cross-space results need an explicit completion or action mechanism; ordinary unwind payloads do not cross roots.

The implemented surface uses `RootRouter.current`, `Router.dismissSpace()`, `RootRouter.dismissSpace(_:)`, and `RootRouter.dismissSpaces()`. Owner-level global reset and cross-space result delivery remain outside this change.

## Implementation notes (2026-10-08)

High and critical base builders accept only modal expressions at compile time. Entry roots have no X parent; their outer presentation does not occupy a Y slot. Local hosted projections derive from the owning space. Owner removal plans capture exact space objects, preserve the whole outgoing tree for snapshots, and remove the space through one ownership edge. Replacement commits the incoming root immediately and waits for outgoing teardown through the same global transaction mechanism used by local transitions. Scoped requests capture their source before resolution, recheck it on readiness, and reject covered sources. Branch selection is canonical model state; native selection synchronization restores its retained value when covered.

An accepted staged replacement checks its requesting scope before its own preparation mutates navigation. On iOS 17, preparation must pop a pushed child before replacing its enclosing selection. That operation continues from its captured presentation anchor after the child leaves; the anchor must still belong to the live top space. A fresh request from the removed child remains inactive. The native regression and a public-routing package regression verify this distinction without weakening the covered-space gate.

## Combined validation (2026-10-08)

The final implementation includes hook-source composition, duplicate-key conflict handling, exact live-tree hook eligibility, and the combined presentation/selection binding supplied by `.routing(branch:)`.

| Check | Result |
| --- | --- |
| macOS package suite | 308 tests in 21 suites passed. |
| iOS 27 package suite | All 303 tests passed. |
| iOS 17.5 package suite | All 303 tests passed. |
| Full iPhone/iOS 27 SampleApp UI suite | 39 passed, with the two expected iPad-only skips. |
| iPad/iOS 27 UI cases | Both passed, completing all 41 UI cases across iPhone and iPad. |
| iPhone/iOS 17.5 native regressions | All five passed: native Back/re-push, replacement from a child, outgoing sheet-stack retention, elevated-root reset/removal followed by normal presentation, and owner removal of covered high while critical remains visible. |
| Mounted macOS presentations | Five tests covering six cases passed, including both elevated fade priorities. |
| Modal-only entry builder | Valid sheets/covers and their nested full builders compile; base Push, Replace, Branches, and unrestricted RouteMap expressions are rejected at compile time. |

The iOS 17 replacement regression was reproduced through both native UI and ordinary public routing before the fix. The existing native assertions remain unchanged. After the fix, the full iPhone suite, iPad cases, both iOS package suites, and the selected older-system regressions were rerun on unchanged production and sample source.

Final production source contains 8,185 Swift lines, compared with 10,502 before the rewrite: 2,317 fewer lines (22 percent). Navigation uses actual independent entry roots and exact scope identity rather than cross-space ancestry recovery. Scope-bound navigation and owner removal have separate handles; local and elevated mutations share global transition coordination. No separate lifecycle ledger, duplicate hook-installation signal, mount-order hook winner, or recursive branch-clearing cascade remains. The synthetic native presentation base and global outgoing-snapshot sequencing remain intentional.

The complete native results are preserved under XcodeBuildMCP's Departure result bundles, including `test_sim_2026-10-08T08-13-30-535Z_pid78295_3100cf14.xcresult` (full iPhone), `test_sim_2026-10-08T08-37-42-774Z_pid80984_c7d9b473.xcresult` (iPad), `test_sim_2026-10-08T08-40-23-936Z_pid81591_939c3446.xcresult` (iOS 27 package), `test_sim_2026-10-08T08-41-50-782Z_pid81917_4221e5f9.xcresult` (iOS 17.5 package), and `test_sim_2026-10-08T08-43-20-281Z_pid82106_14b5ce7f.xcresult` (older-system native regressions).

A final observed simulator interaction verified clean root → high sheet, high removal → normal sheet, and normal Done → clean root on iOS 27. Screenshot and hierarchy evidence establish those completed states. Recording under the UI automation backend interfered with taps, and the saved recording did not capture the transition sequence. Initial-frame blink prevention and precise animation-frame ordering therefore remain visually unverified; the source retains nonanimated base insertion and animation triggered after window installation, and the native suites validate presentation outcomes and chaining. No routing change or assertion relaxation was made for the failed recorded taps.

Local visual evidence is preserved in `/tmp/departure-space-visual-report.md`, `/tmp/departure-space-visual-high.jpg`, `/tmp/departure-space-visual-normal.jpg`, and `/tmp/departure-space-visual-after-done.jpg`. The saved `/tmp/departure-space-visual-retry.mp4` and inspected contact sheet contain no transition proof.
