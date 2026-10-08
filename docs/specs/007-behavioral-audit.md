# Behavioral audit

Status: review inventory of the implementation on `zaquia/predefined-route-maps`. The descriptions below record current behavior. The first accepted changes are recorded below; the remaining recommendations are proposals.

This audit reopens inherited rules as well as new rules. Specifications 1–6 remain the implemented contracts until a decision here explicitly changes them. Passing tests establish the current behavior; they do not establish that a rule is desirable.

## How to review

Review one group at a time. For each rule, choose **keep**, **change**, or **remove**, then specify the consumer-visible result with a concrete example. A convenience should have one understandable default and an explicit way to express a different intent. Prefer existing explicit targets, such as `router.branch(id)`, over a collection of interacting fallback flags.

The X/Y/Z ownership constraints, consumer-facing navigation choices, and native presentation mechanics are separate review subjects. A one-modal-per-lane constraint does not by itself choose which modal a new request replaces. Exact source identity does not by itself choose whether covered requests are rejected on arrival or after a queue drains.

## First decisions

| Decision | Current rule | Decision or proposal |
| --- | --- | --- |
| Where may a plain presentation search? | Selected branch's current local scope, selected branch map, the node's own map, sibling branch maps in declaration order, then ancestors; elevated entries have a separate root-catalog fallback. | Retain website-like automatic selection of the matched destination's owning tab. Investigate ambiguity and nested branch-root discovery in specification 8; explicit targeting should resolve ambiguous intent rather than be required for every sibling transition. |
| What does route equality mean for navigation? | `Equatable` enables automatic reuse and unwinding within the matched path; replacement uses its selected slot and an elevated entry uses its own root. | Make reuse an explicit navigation contract. Ordinary data equality should not silently choose a navigation operation. Decide the default before designing its API. |
| Who may act while a space is covered? | Scoped navigation and router-dispatched actions require the live top space. `RootRouter.default` captures the default flow for external entry points; `current` captures the top space. Explicit owner removal can still remove covered elevated spaces. | Accepted and implemented: deep links must not inherit a lockscreen's authority, execute behind it, or dismiss it. Deferred action invocations recheck the same gate. |
| When does a queued request get rejected? | Live presentation sources may enter the latest slot during an unfinished operation, even while covered. Removed sources are rejected immediately; coverage is checked on execution. | Accepted: buffer first, then evaluate against the completed unwind. A retained higher space still causes the request to drop. |
| How are invalid declarations handled? | Duplicate route, branch, and hook keys report a diagnostic and disable that key. Route/hook conflicts stop lookup instead of choosing a winner or falling back. | Duplicate policy accepted and implemented. Missing branch-binding behavior remains a separate open configuration decision. |
| When are unwind handlers notified? | Native and explicit unwinds enter the matching handler before commit, with routing suspended by the accepted operation. The unwind continues when the handler suspends; handler presentations wait for operation completion. | Timing accepted and implemented. Deduplication and local lookup-origin rules remain unchanged; `.nearestBranch` versus explicit branch-root lookup remains open for review. |

The initial authority, duplicate, and handler-timing decisions were implemented on 2026-10-08. Other recommendations remain unapproved and do not change runtime behavior. Ordinary app background work is outside router command authority. An already-running asynchronous action is not forcibly cancelled when covered, but further dispatch, deferred invocation, and routing continuation must revalidate authority.

A second accepted pass implements D3, D6, D9, O2, and O5: restricted modal-map composition, one explicit map ID per receiving scope, a Branch-only group builder, `default` flow terminology, and the distinction between live command authority and active phase. A subsequent accepted change lets lower-space unwind handlers receive notification and buffers live presentation attempts until unwind completion before checking coverage. E6 now restricts unwind notification to explicit unwind/removal requests and native dismissal, excluding presentation crawlback, reuse, and replacement. B4, B6, and B10 now add binding mismatch guidance, one `Branches` group per receiving scope, and one mounted selection binding owner. Recommendations outside the accepted rows remain open.

## 1. Maps, route identity, and configuration

Evidence: [route builders](../../Sources/Departure/Attachments/Declarations/RouteDeclaration+Builders.swift), [compiled definitions](../../Sources/Departure/Router/RouteDefinitions.swift), [engine configuration](../../Sources/Departure/Router/RouterEngine.swift), [route protocol](../../Sources/Departure/Protocols/Route.swift), and `DeclarationTests` / `RouteDestinationTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| D1 | `RootRouteMap` supplies default definitions and optional high/critical entry builders. Higher-priority builders accept `Sheet`, `Cover`, and restricted `ModalRouteMap` composition; their children accept the full builder. | Keep the explicit modal-only origin requirement. |
| D2 | `RouteMap` composition flattens declarations into the insertion scope. It adds no runtime scope or lookup boundary. | Keep; make the distinction between composition and scope creation clear. |
| D3 | Elevated builders compose `ModalRouteMap` values, whose base grammar accepts only sheets, covers, and other modal maps. Their child builders accept ordinary maps and all local styles. | Accepted: retain compile-time modal restrictions with a restricted composition type. |
| D4 | Route and branch definitions exist independently of view installation. Runtime branch roots are created from definitions, and destination instances receive their own child definitions when inserted. | Keep as the map model's foundation. |
| D5 | The owner accepts its map once. A later `WithRouter` using the same owner does not replace its definitions; conditional map expressions are evaluated when the supplied map is constructed, not continuously reconciled into the owner. | Document static configuration, or design an explicit reconfiguration operation. |
| D6 | Declaration matching is by exact route type. `RootRouteMap(id:)`, `RouteMap(id:)`, and presentation declaration IDs explicitly name receiving scopes for unwinding. One explicit ID is allowed per scope; conflicts diagnose and disable that explicit target without disabling destinations. | Accepted map-level IDs: distinguish repeated route types with explicit scope names; composition adds no scope. |
| D7 | The same route type can appear at different map occurrences. At one scope, duplicate route types report a diagnostic and disable that key. Default, high, and critical root declarations are concatenated into one root definition set, so the same type repeated across those catalogs also conflicts. | Accepted: one conflict policy with hooks; no declaration-order winner and no ancestor/sibling fallback past a conflict. |
| D8 | Duplicate branch values report a diagnostic and disable that branch; no runtime scope is created for it. Inserting the same reusable map at different occurrences compiles independent declaration occurrences. | Accepted duplicate policy; keep occurrence identity. |
| D9 | `Branches` uses `BranchDeclarationBuilder`, accepting only `Branch` expressions with conditional and loop composition. Other declarations are siblings of the group in the enclosing map. | Accepted: invalid branch-group expressions fail at compile time. |
| D10 | Destination view factories are captured by the compiled map. Environment/context values are refreshed when building the view, but changing a later map value does not replace the original factory. Hook callbacks, by contrast, refresh with their installed modifier source. | Document the lifetime of captured definitions versus live context. |

## 2. Owners, scopes, and command sources

Evidence: [RootRouter](../../Sources/Departure/Router/RootRouter.swift), [Router and origins](../../Sources/Departure/Router/Router.swift), [scope membership](../../Sources/Departure/Router/RouteScope.swift), `ScopedRouterTests`, `IndependentPriorityTests`, and `RouteOwnershipTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| O1 | `RootRouter` owns the engine. `Router` is a weak, scope-bound handle; environment defaults outside `WithRouter` are inactive. Captured routers do not keep their scopes or owners alive. | Keep exact ownership and harmless default handles. |
| O2 | `RootRouter.current` captures the top space's current source at access time; `default` captures the default flow's current source even while covered. Stored values retain exact source identity. | Accepted: `default` names the ordinary flow throughout the library, including `RoutePriority.default`. Use current deliberately for top-space authority. |
| O3 | Current-scope selection follows the continuation and selected branch of the highest-priority space. Modal-lane occupancy is calculated separately. | Stress-test a modal on one concurrent branch while another branch becomes selected; define what `current` should mean. |
| O4 | A removed scope's router never falls back to a surviving ancestor or replacement instance. An outgoing retained view is already inactive for routing. | Keep; this prevents stale callbacks from redirecting navigation. |
| O5 | Command authority requires live membership in the top space, independent of phase or host installation. Inactive ancestors and unselected branches there may issue commands; lookup, branch activation, and readiness rules still apply. Active phase means a current endpoint within a participating path and current modal subtree; concurrent branches may each be active. Covered and removed scopes are always inactive and ineligible. | Accepted and documented: membership determines command authority; phase describes foreground position. |
| O6 | A branch router captures the owning container and an ordered branch address. It resolves that address's active local scope when a command runs; it survives dismissal of the destination that requested the handle, but not removal of its container. | Keep explicit branch targeting; distinguish it from a fixed destination handle. |
| O7 | Getting a branch handle does not select the branch. Missing or removed branch addresses are inactive; chained `branch` calls address nested branch containers and do not fall back to an ancestor's similarly named branch. | Keep no-retargeting and explicit target boundaries. |

## 3. Declaration discovery

Evidence: [scoped declaration search](../../Sources/Departure/Router/RouteSpaces.swift), [attachment ordering](../../Sources/Departure/Router/RouteScope+Declarations.swift), `NestedBranchLookupTests`, `ScopedRouterTests`, and the branch lookup cases in `RouterTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| L1 | Search begins from the requesting handle's resolved source, rather than always from the owner's global current destination. Missing matches walk backwards through that source's navigation ancestry within its space. | Keep one canonical meaning for nearest match. |
| L2 | For a plain request, a container can first discover a declaration on its selected branch's active local destination. This can win over a declaration directly on the container. | Decide whether looking forward into a selected branch belongs in nearest-node semantics. |
| L3 | At a branched node, ordinary lookup prefers the selected branch's root map, then the node's own map, then other branch root maps in declaration order. | Review selected-branch precedence and first-sibling fallback separately. |
| L4 | A sibling fallback can select that branch automatically. Reordering branch declarations can therefore change where an otherwise identical request is presented. | Keep automatic reveal of the matching owner. Specification 8 investigates replacing declaration-order ties with ambiguity handling while retaining convenient tab selection. |
| L5 | Plain lookup does not search every sibling's deeper history or every uninstantiated descendant declaration. A branch-root map and that branch's current destination are different lookup locations. | Make the search boundary understandable; avoid calling it a search of the entire predefined tree. |
| L6 | Explicit branch handles do not use sibling-branch fallback. They can still climb to a common ancestor declaration. A reroute to such a common ancestor reveals the presentation owner's ancestry rather than the originally requested branch. | Decide whether ancestor escape is the intended meaning of an explicit branch address. |
| L7 | Space ancestry never crosses a priority boundary. After local search fails, the default root's catalog can supply an elevated entry; default-flow declarations cannot be found through that cross-space fallback. | Keep the explicit distinction between local definitions and the owner's entry catalog. |
| L8 | A declaration is chosen before equality reuse and priority decisions. A matching equal value elsewhere is not a global address that bypasses declaration lookup. | Keep or replace with a deliberately addressed navigation API. |
| L9 | A missing declaration drops the request with a diagnostic. `present` returns `Void`, so its caller has no structured accepted/dropped result. | Consider whether consumers need a result for critical flows or external entry points. |

## 4. Equality and reuse

Evidence: [route equality](../../Sources/Departure/Utils/Route+Equality.swift), [transition decision](../../Sources/Departure/Router/Router+RouteDeclaration.swift), [equivalent-route search](../../Sources/Departure/Router/Router+Navigation.swift), `ReplaceTests`, `UnwindPresentationPolicyTests`, and equivalent-route cases in `RouterTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| E1 | Equality requires the same route type and an `Equatable` conformance. Non-equatable routes are never considered equivalent, even if their type-based IDs match. | Decide whether ordinary data conformance should opt into navigation reuse. |
| E2 | A matching current destination can be a no-op only when its presentation provenance agrees with the selected declaration host and style. Explicit branch targeting still reveals that branch. | Preserve occurrence correctness; make the selection side effect visible. |
| E3 | For push/modal reuse, the chosen presentation path is searched backwards, ending at the matched presentation anchor. The nearest eligible equal value is retained and destinations after it are unwound. Other branch paths and spaces are not searched for equal values. | Document the reuse boundary; decide whether it should be implicit. |
| E4 | `Replace` compares the selected structural slot, not an equal value pushed deeper on the same path. Equal replacement retains the selected instance and removes its children. | Keep as a consequence of slot replacement, if reuse is enabled. |
| E5 | Equal elevated entries reuse that space's exact root and reset its local navigation; an unequal entry creates a new space instance. Reset preserves only the retained root's own inactive branch pushes. | Review reuse intent separately from whole-space replacement. |
| E6 | A presentation never invokes unwind handlers, including ancestor crawlback, equality reuse, and replacement. Handlers report explicit unwind/removal requests and native Back or dismissal. Reuse keeps the retained route data/view instance. | Accepted and implemented: structural removal during presentation is not an unwind notification. Preserve existing teardown and snapshot policy. |

## 5. Presentation anchors and X/Y/Z constraints

Evidence: [transition plans](../../Sources/Departure/Router/RouteSpaces.swift), [declaration anchors](../../Sources/Departure/Router/RouteScope+Declarations.swift), [X ownership](../../Sources/Departure/Router/RouteScope.swift), [modal lanes](../../Sources/Departure/Router/RouteLane.swift), and `RouteSpaceTests` / `ReplaceTests` / `RouterTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| P1 | A destination extends exactly one owned X path. Push and replacement stay in the same Y lane; a local modal extends X, occupies its presenting lane's one modal slot, and starts a child Y lane. | Keep the core ownership constraints. |
| P2 | Branch roots share their parent's X position and Y lane, and each owns an independent X continuation. Branches do not create extra modal capacity. Priority roots own separate spaces and start at X=0/Y=0. | Keep the defined geometry. |
| P3 | The declaration's location, the presentation anchor, and the requesting source can differ. A branch-root declaration generally presents from the branch root; a declaration found on its active local destination presents from that local destination. | Decide which anchors need explicit consumer-visible naming. |
| P4 | A new nonmodal request removes the continuation after its presentation anchor before insertion. Finding an ancestor declaration may therefore pop children, remove a modal, or reset a branch selection's child path. | Document the destructive consequence of ancestor matching. |
| P5 | A new modal replaces the existing modal occupying that presentation anchor's lane, including a modal from another branch sharing that lane. A request from within a modal uses its child lane and can nest another modal. | Keep one slot; decide whether replacement is automatic or explicit intent. |
| P6 | When presentation and declaration paths differ, the declaration path is also trimmed after its declaring location. Other independent branch histories are retained unless an owning container is removed. | Verify concrete ancestor/sibling scenarios before simplifying this consequence. |
| P7 | `Replace` renders a structural content slot with its own destination scope and children. It adds no native Back entry and occupies no modal slot. Unwinding that selection restores the placeholder content. | Keep the explicit replacement capability. |
| P8 | Removing a scope removes its entire owned continuation and every owned branch, including inactive histories. Resetting a retained branched root clears participating branch paths but preserves that root's inactive pushed histories; inactive modals are still removed. | Keep ownership-based removal; explicitly state the root-retention exception. |

## 6. Branch participation and selection

Evidence: [branch declarations](../../Sources/Departure/Attachments/Routes/Branch.swift), [branch state](../../Sources/Departure/Router/BranchContainerState.swift), [selection binding](../../Sources/Departure/Router/SwiftUI/AnyRouteBranchSelection.swift), [branch activation](../../Sources/Departure/Router/Router+Navigation.swift), and `ScopedRouterTests` / `ReplaceTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| B1 | The first declared branch is initially selected until a selection binding supplies another value. | Keep a default only if declaration order is deliberately part of the API. |
| B2 | Exclusive containers have one participating branch. Concurrent containers let every branch participate, while still maintaining one selected branch for current-source selection. | Keep the separate concepts of participation and selection. |
| B3 | Selecting another branch retains independent branch histories. A successful presentation targeting a branch can write the consumer's selection binding; rejected/missing routes do not select it. | Keep explicit target convenience, with a clear accepted-navigation boundary. |
| B4 | A branch value that cannot be represented by the binding's selection type rejects activation without changing navigation. A diagnostic identifies the value and both types and recommends aligning `Branch` values with `.routing(branch:)`. Covered native synchronization restores the model selection. | Accepted and implemented: useful guidance on mismatch; compatible optional bindings remain supported. |
| B5 | The public selection modifier accepts whatever value the binding currently contains. Unknown or optional empty values can leave no known branch selected; obtaining a matching explicit branch router still requires an actual declaration. | Define empty selection versus invalid selection rather than relying on incidental fallback. |
| B6 | A scope accepts exactly one `Branches` group, including through composed maps. Concurrency is compiled once for that container. Bare `Branch` expressions outside the group are rejected by the builder. Multiple groups diagnose and disable the container while retaining sibling routes. | Accepted and implemented: one group per container, including when repeated groups have equal concurrency or are empty. |
| B7 | An exclusive branch change can leave a presentation awaiting branch continuation. Concurrent branches can append immediately. The pending continuation can resume after a scheduled turn or host attachment; `present` does not universally mean the destination has mounted. | Keep convenience while specifying completion semantics. |
| B8 | A surviving branch host can resume an already accepted replacement while its outgoing native scopes finish. Global new requests remain buffered until operations complete. Cancelled accepted continuations cannot be revived by a host refresh. | Keep this native compatibility behavior separate from general request policy. |
| B9 | Nonmodal bindings can continue to represent unselected exclusive branch history; modal presentation drivers require branch participation. | Review whether this distinction is a presentation consequence or a consumer rule. |
| B10 | The model owns one selected value. A mounted container accepts one `.routing(branch:)` binding owner, derived from routing attachments. Duplicates diagnose, retain selection, and disable selection changes until one remains. Plain routing hosts do not compete for selection ownership; detachment retains model state. | Accepted and implemented: exactly one connected selection owner, no update-order winner or separate selection registry. |

## 7. Priority spaces and owner capabilities

Evidence: [spaces](../../Sources/Departure/Router/RouteSpaces.swift), [priority decisions](../../Sources/Departure/Router/Router+RouteDeclaration.swift), [owner operations](../../Sources/Departure/Router/RootRouter.swift), and `IndependentPriorityTests` / `ElevatedLifetimeTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| S1 | There is one permanent default space and at most one high and one critical space. The highest existing space is active; lower spaces retain their own navigation state. | Keep the explicit independent-space model. |
| S2 | Presentations commit only from live sources in the top space. During an unfinished operation, live covered presentation attempts wait and are checked on resumption. Scoped unwind/removal, actions, deferred invocation, branch activation, and native write-back retain immediate coverage gates. | Accepted: delay presentation evaluation without permitting navigation behind a surviving higher space. |
| S3 | An eligible source in the top space can open an equal-or-higher elevated entry from the owner's catalog. A lower-priority entry request is dropped while a higher space exists. Local child declarations run within the current space. | State the entry rule independently from local presentation style. |
| S4 | The elevated entry destination is the space root. Its outer modal does not occupy a lane inside that space. Local root unwind keeps the outer modal; its root's `unwindRoute` removes the space. | Keep the explicit root distinction. |
| S5 | `Router.dismissSpace()` removes its exact top elevated space from any depth. `RootRouter.dismissSpace(priority)` can remove the addressed covered space. `dismissSpaces()` captures all currently existing elevated instances in one accepted operation. | Keep the covered removal capability on the explicit owner API. |
| S6 | Owner removal leaves other spaces intact. Absent elevated priorities, `.default`, and plural removal with nothing to remove return `false`. A later replacement is protected from an earlier command's stale callbacks. | Keep exact-instance removal and a permanent default root. |
| S7 | Logical removal exposes the next top space immediately, but globally buffered presentations wait for native teardown. Unequal elevated replacement installs its incoming root before awaiting the outgoing instance, so it exposes no temporary lower-space gap. | Keep atomic logical replacement and explicit completion ordering. |
| S8 | Unwind ID targets stay within their space. Unwind notification and typed payloads can reach a surviving lower-space handler. Whole-space owner removal has no public payload overload. | Accepted lower-space notification; command ancestry remains independent. |
| S9 | Physical detachment of a still-current elevated root removes that exact space even outside an explicit navigation request. Stale root teardown cannot remove a replacement instance. Root/branch definitions otherwise survive host detachment. | Decide whether automatic elevated retirement is an intended lifecycle contract. |

## 8. Unwind targets and completion

Evidence: [unwind execution](../../Sources/Departure/Router/Router+Navigation.swift), [path targets](../../Sources/Departure/Router/RoutePath.swift), [unwind action](../../Sources/Departure/Environment/Environment+RouteScope.swift), `UnwindHookTests`, `ScopedRouterTests`, and unwind cases in `RouterTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| U1 | `.root` resets the receiving space, retaining its root. It returns `false` when there is nothing to remove. | Keep local root semantics. |
| U2 | `.topmostAncestor` and `unwindRoute()` dismiss the captured receiving destination and its descendants, rather than invariably the owner's foreground destination. On an elevated root they remove the whole space. | Naming should communicate scope-local dismissal. |
| U3 | `.nearestBranch` clears the nearest branch path, keeping its branch root; outside a branch it returns `false`. An already empty addressed branch is retained. | Decide the accepted-no-op result; avoid suggesting that an empty branch escapes to a parent path. |
| U4 | `.id(value)` first recognizes the path owner's ID, otherwise the deepest matching ID in that path, then resolves through enclosing branch/container paths. It retains the target. IDs do not address declarations globally or cross spaces. | Review duplicate IDs and owner-first versus nearest-instance precedence. |
| U5 | The Boolean generally reports that an active target was accepted. An ID/branch target can be accepted with no removals, whereas an empty `.root` returns `false`. | Define whether success means target found or actual mutation; current cases differ. |
| U6 | Logical path removal is immediate when committed. Awaiting an unwind/removal waits for the removed scopes that were installed to leave, plus required outgoing-projection release; it does not wait for asynchronous handler bodies. | Keep distinct mutation, native completion, and callback completion. |
| U7 | Cancellation before commit prevents the change; cancellation after committed removal does not restore the outgoing tree. A cancelled replacement finishes cleanup without inserting its continuation. | Keep irreversible accepted-removal semantics explicit. |
| U8 | Multiple accepted unwinds/owner removals can overlap. Plans protect exact captured structures and merge path trims through their shallowest retained positions; completion order does not erase another operation's projections. | Preserve robustness; decide how much ordering consumers can rely on. |

## 9. Global readiness, buffering, and resolution

Evidence: [navigation operations](../../Sources/Departure/Router/NavigationOperation.swift), [readiness gate](../../Sources/Departure/Router/Router+Navigation.swift), [route resolution](../../Sources/Departure/Router/Router+RouteDeclaration.swift), `NavigationOperationTests`, `NavigationReadinessTests`, and pending-request cases in `RouterTests` / `ReplaceTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| Q1 | Unfinished accepted operations globally suspend new presentations across branches and priorities of the same owner. Independent owners have independent coordination. Unwinds themselves are not serialized behind that presentation queue. | Keep one owner-wide coordination rule; document overlap. |
| Q2 | The queue retains one latest live request. A newer queued request replaces the older and resumes its caller without presenting it, even if the new source is covered. Removed sources never enter the slot. | Accepted latest live attempt; coverage is checked after the operation completes. |
| Q3 | On drain, captured source membership and coverage are revalidated, then the remaining resolution/declaration/equality/priority rules run against current state. A route that already finished resolution keeps that stage and is not resolved a second time. | Accepted delayed coverage evaluation and exact stage ownership. |
| Q4 | A lower-space handler notified before MFA removal can buffer a default presentation. It waits for native exit and proceeds if no higher space remains; it drops after a root reset or partial unwind that retains coverage. The removed MFA source cannot serve as the default-flow origin. | Accepted handoff and retained-space rejection, including latest-request supersession. |
| Q5 | `resolveRoute()` defaults to `.allow`. Each `.reroute` resolves the new candidate again; `.drop` ends the request. There is currently no route-reroute cycle detection or hop limit. | Choose an explicit loop/failure contract; avoid an arbitrary hidden heuristic. |
| Q6 | Route resolution can suspend. A source that becomes covered or removed before resolution completes cannot commit; new operations that begin during resolution are honored by re-entering the readiness gate. | Keep revalidation at asynchronous boundaries. |
| Q7 | A queued request owns its execution cancellation after it leaves the slot. Cancelling the unwind that releases the queue does not cancel unrelated pending work. Superseded/cancelled callers are resumed once. | Keep independent caller cancellation. |
| Q8 | Global request waiting and an accepted branch presentation use the same latest slot but represent different stages. Waiting for a branch after native teardown does not keep global navigation busy, and a newer request can replace that continuation. | Decide whether this single-slot supersession is the intended public contract. |
| Q9 | `await present` can complete after a no-op, a drop, supersession, state insertion, or creation of a branch continuation. It does not guarantee a displayed destination, a mounted view, or a retryable result. | Consider a structured outcome rather than inferred readiness. |

## 10. Hooks and unwind results

Evidence: [hook composition](../../Sources/Departure/Router/RouteScope.swift), [hooks modifier](../../Sources/Departure/Modifiers/View+Hooks.swift), [unwind handler](../../Sources/Departure/Attachments/Hooks/UnwindHandler.swift), [handler delivery](../../Sources/Departure/Router/Router+Navigation.swift), and `HookBindingTests` / `UnwindHookTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| H1 | Distinct `.hooks` sources compose by hook kind and route/action type. Updating/removing one source changes only that source's declarations and captured callbacks. | Keep composition without mount-order precedence. |
| H2 | Duplicate keys, within or across sources, disable that hook until only one remains. A conflict blocks ancestor fallback and does not bypass an interceptor to execute an action directly. | Keep deliberate conflict handling; align other declaration conflicts. |
| H3 | Hooks participate only while their exact scope belongs to the live tree. Outgoing snapshots retain closures/views for teardown without behavioral eligibility. Live covered scopes can receive unwind notification but cannot dispatch actions or invoke deferred action bodies. | Accepted notification in covered scopes; command authority remains a separate top-space requirement. |
| H4 | An unwind handler is chosen for the initiating source route type, starting at the surviving landing scope and climbing to its root. If none matches, each surviving lower space is searched from its current scope to its root, nearest priority first. Only the nearest match runs; conflicts stop fallback. Removed descendants and sibling paths are not searched. | Accepted lower-space notification without cross-space navigation ancestry. |
| H5 | `.nearestBranch` starts local lookup at the enclosing container; `.id(branchRootID)` starts at the retained branch root. Whole-space removal starts directly with lower spaces. Combined removal skips spaces also being removed and notifies for captured roots in descending priority. | Lower-space fallback accepted; target-specific local origins remain open for review. |
| H6 | Payload handlers require a successful cast to their payload type. A missing/mismatched payload logs and skips that selected handler; it does not search for an ancestor with a compatible payload. No-payload handlers ignore payloads. | Keep or change typed mismatch behavior deliberately. |
| H7 | Native and explicit accepted unwinds and explicit whole-space removal enter matching handlers before logical commit. Presentation crawlback, reuse, and replacement do not notify. The unwind operation suspends presentations through notification and teardown; follow-ups recheck coverage on resumption. The unwind does not await asynchronous handler completion. Native write-back without a handler can commit synchronously. | Accepted uniform timing, delayed coverage evaluation, and the E6 distinction between dismissal requests and presentation cleanup. |
| H8 | Delivery is deduplicated by source instance and matched target scope ID. Overlapping explicit/native requests share the same handler-entry task, so none can commit ahead of that notification. A notified handler may already run even if later cancellation/eligibility prevents commit. | Accepted before-commit event and shared entry boundary. Review value-ID versus target-instance identity and cancellation effects. |
| H9 | Losing live membership prevents future hook lookup and stale deferred invocation. It does not automatically cancel a handler or action body that has already begun executing across an asynchronous suspension. | State the boundary between routing authority and consumer-owned asynchronous work. |

## 11. Actions and interception

Evidence: [action API](../../Sources/Departure/Protocols/Action.swift), [action dispatch](../../Sources/Departure/Router/Router+ActionInterceptor.swift), [invocation](../../Sources/Departure/Attachments/Hooks/ActionInterceptor.swift), and `ActionHookTests` / `HookBindingTests` / `ScopedRouterTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| A1 | `Router.perform` starts at its captured resolved source. It looks for an interceptor on that exact scope; it does not crawl ancestors for an interceptor. A branch-root action context can inherit its parent's route type. | API comment now reflects captured origin; decide whether route-type inheritance is intentional. |
| A2 | Only a live source in the top priority space can dispatch an action or enter its interceptor. Actions are not queued solely because a navigation operation is unfinished. | Accepted covered-space gate for router commands; unrelated background application work remains outside that gate. |
| A3 | An interceptor can call, defer, suppress, or repeatedly call `invocation()`. Invocation validates that the intercepting scope is still live in the top space, then uses the original routing origin. Removal or coverage throws `CancellationError`. | Accepted coverage revalidation; single-use invocation and branch-address pinning remain open. |
| A4 | Action `.reroute` schedules navigation, ends the current invocation with cancellation, waits for the selected target to install where applicable, and retries through that target's interceptor. The action retries only once. | Keep intentional forwarding, but expose what `await perform` completes. |
| A5 | A routing request returns its matched space, or nil for declaration/resolution/authority rejection or supersession in the latest request slot. Action retry uses that exact space and a surviving local continuation owner; it cannot fall back to an unrelated foreground space. | Covered-reroute protection implemented. A matched-space result alone does not prove insertion; review staged append supersession and destination-installation outcomes separately. |
| A6 | `.invocationError` is thrown to a calling interceptor. Direct un-intercepted action dispatch catches and logs failures; public `perform` returns no result. An action's `Output` is available to its interceptor, not to the public caller. | Decide whether this is fire-and-forget work or an awaitable request/result API. |
| A7 | Reroute retry runs in an unstructured task. Its installation wait is completed by host installation, with no cancellation or logical-removal wake-up in that waiter. The initiating `perform` caller does not own the retry's completion. | Establish cancellation and never-installed/removed-target scenarios before promising an awaitable action flow. |

## 12. View bindings, environment, and native presentation

Evidence: [routing modifiers](../../Sources/Departure/Modifiers/View+Routes.swift), [attachments](../../Sources/Departure/Router/RouteScopeAttachment.swift), [binding projections](../../Sources/Departure/Router/SwiftUI/Router+Presentation.swift), [route context](../../Sources/Departure/Views/RouteDestination.swift), [route phase](../../Sources/Departure/Environment/Environment+RouteScope.swift), [elevated hosts](../../Sources/Departure/Views/ElevatedPriorityHost.swift), and `PresentationHostOwnershipTests` / `RouteScopeHostTests` / `WindowDestinationBuilderTests` / native UI tests.

| ID | Current behavior | Review point |
| --- | --- | --- |
| V1 | `WithRouter`, route destinations, and `.routing(branch)` install automatic presentation bindings. An explicit `.routing()` wins over automatic bindings at the same scope. Multiple explicit hosts use the last registered host; other hosts stop driving presentation. | Keep convenience, but review implicit host competition/mount-order ownership. |
| V2 | `RoutedNavigationStack` is convenience for `NavigationStack` with a routed root. No route declaration auto-wraps a destination in a stack. A Push needs a consumer-supplied navigation container; modal-only scopes do not install push destinations. | Keep explicit navigation-container ownership. |
| V3 | `.routing(branch:)` binds both container selection and presentation. `.routing(branchValue)` enters a predefined branch; a missing branch silently leaves ordinary content in its inherited scope. Routing views outside a live `WithRouter` owner can precondition-fail, while ordinary environment router commands outside it are harmless. | Make missing configuration uniformly diagnosable. |
| V4 | Registrations attach only to views physically owned by the exact managed scope. External legacy SwiftUI presentations cannot replace that scope's routing/hooks; a transient missing anchor leaves registration pending, and anchor installation retries it. | Keep ownership checks as native mechanics, not route-discovery heuristics. |
| V5 | Native dismissal writes only remove the expected exact current presentation. Non-nil writes, stale bindings, outgoing-only projections, wrong hosts/styles, and covered-scope dismissals cannot mutate live navigation. | Keep exact-instance native reconciliation. |
| V6 | `RouteContext` supplies a scope-bound router/unwind action, actual presentation style and owning priority, and current destination environment. An ordinary push inside high priority reports high priority even though its declaration is local. | Keep destination context independent of wrapper views. |
| V7 | Detached destinations use the owner's `windowDestination` builder and captured source environment; this includes elevated presentations and UIKit default fade covers. Consumers explicitly forward required environment values. | Keep one explicit forwarding boundary and clarify capture/refresh timing. |
| V8 | `routePhase` derives from top-space membership, branch participation, local path position, and the deepest modal subtree. Concurrent branches inside the current modal can each be active; scopes outside that modal subtree are inactive. | Document as view-local foreground state, not command authority or installation readiness. |
| V9 | Outgoing modal stacks retain pushed bindings until their modal exits. Push-only multi-unwinds clear bindings together and animate only the outermost removed push. Live bindings take precedence over outgoing projections. | Keep coherent native teardown; avoid exposing snapshot bookkeeping as API. |
| V10 | Elevated UIKit windows install a transparent base without animation before their real entry modal animates. Separate priorities have separate native windows. Sheets retain native scrim/passthrough behavior; UIKit covers use full-screen presentation. | Keep the required animation/priority mechanism as an implementation obligation. |
| V11 | On macOS, both cover transitions use sheet presentation. UIKit fade covers have a staged content fade and delayed native dismissal; slide covers use the system transition. Scene-phase changes trigger reconciliation. | Document actual platform capabilities rather than promising identical animation everywhere. |
| V12 | iOS 17 defers suspicious push nil writes until physical exit, ignores unseen-push dismissal, stages child pops before selection replacement, and uses a two-second view-exit watchdog with exact host identity. These mechanics are unavailable from iOS 18 onward. | Keep only while that platform support is required; audit observable timing separately from core rules. |
| V13 | UIKit elevated presentation uses the source host's window scene when available, otherwise the first active, inactive, or connected scene. No available scene requests route clearing. High windows use alert level minus one; critical windows use alert level. | Define scene ownership explicitly for multi-window consumers and state the limit of priority ordering. |
| V14 | Each elevated native window remembers its previous key window and restores it on teardown. This restoration is independent of the other priority window's continued visibility. | Reproduce keyboard/focus behavior when the owner removes covered high while critical remains; visibility alone does not validate key-window ownership. |

## Verification boundaries and follow-up scenarios

The operation pass validates unchanged public behavior with the package and native suites recorded in specification 6. This audit is a source-and-test inventory, not an assertion that every combination below has been reproduced on a device. Before changing a rule, add or identify a public-routing regression for its agreed replacement.

The first accepted changes have public-routing regressions in `DeclarationTests`, `SpaceAuthorityTests`, and `UnwindHookTests`. They cover conflicting route keys in either order, ancestor/sibling lookup barriers, disabled duplicate branches, repeated types across priority catalogs, covered external actions/navigation, deferred invocation after coverage, resolution interrupted by a lockscreen, intentional rerouting into high priority, and native/explicit handler entry with a suspended follow-up presentation.

The authority and timing regressions were also run against an isolated copy of `37bbbd2`, with only a test-local default-source accessor replacing the absent new public property. They fail there: covered actions execute, deferred invocations remain executable, native handlers observe an already-removed source, and a rejected default reroute reaches the critical lockscreen's interceptor. Intentional high-priority rerouting still passes there and on the new code. Separate public-routing duplicate-route and duplicate-branch regressions also fail on that preceding implementation. The accepted implementation passes these cases without weakening their behavioral assertions.

The fixture bridge used by older package scenarios now fills only missing declaration keys from its compiled fixture branch. It no longer invents duplicate declarations when grafting an explicitly supplied branch map. This is test construction, not a runtime precedence or compatibility rule. Native tests remain unchanged.

A repeated native-write regression caught an intermediate timing race: a second accepted dismissal skipped duplicate notification and committed ahead of the first callback's entry. The existing delivery record now owns one handler-entry task, and all requests sharing that delivery await it. Four timing cases cover single explicit, single native, repeated native writes, and overlapping explicit unwinds. They require the source to remain live at callback entry, exactly one notification, and follow-up presentation to wait for teardown. No new registry or lifecycle flag is added.

Validation of the first accepted pass (2026-10-08): every run below passed with no failures. The complete UI matrix covers all 41 cases: 39 on iPhone and the two iPad-only cases on iPad. The UI suite's assertions remain unchanged.

| Run | Result | Evidence |
| --- | --- | --- |
| macOS package | 322 tests in 23 suites passed | [Log](/tmp/departure-decisions-macos-clean.log) |
| iPhone UI, iOS 27 | 39 passed; 2 iPad-only skips | [Log](/tmp/departure-decisions-ui-full-final2.log); [result bundle](/Users/mtrezaq/Library/Developer/XcodeBuildMCP/workspaces/Departure-e3c91e6d130e/result-bundles/test_sim_2026-10-08T11-28-49-148Z_pid8815_548a49ee.xcresult) |
| iPad UI, iOS 27 | 2 passed | [Log](/tmp/departure-decisions-ui-ipad-final2.log); [result bundle](/Users/mtrezaq/Library/Developer/XcodeBuildMCP/workspaces/Departure-e3c91e6d130e/result-bundles/test_sim_2026-10-08T11-52-29-168Z_pid11447_72c45f9a.xcresult) |
| iOS 27 package | 317 passed | [Log](/tmp/departure-decisions-package27-clean.log); [result bundle](/Users/mtrezaq/Library/Developer/XcodeBuildMCP/workspaces/Departure-e3c91e6d130e/result-bundles/test_sim_2026-10-08T12-00-17-768Z_pid13136_cd7936c2.xcresult) |
| iOS 17.5 package | 317 passed | [Log](/tmp/departure-decisions-package17-clean.log); [result bundle](/Users/mtrezaq/Library/Developer/XcodeBuildMCP/workspaces/Departure-e3c91e6d130e/result-bundles/test_sim_2026-10-08T12-00-42-435Z_pid13248_869627d6.xcresult) |
| iPhone UI regressions, iOS 17.5 | 5 passed | [Log](/tmp/departure-decisions-ui-17-final2.log); [result bundle](/Users/mtrezaq/Library/Developer/XcodeBuildMCP/workspaces/Departure-e3c91e6d130e/result-bundles/test_sim_2026-10-08T11-55-10-589Z_pid12345_fb4e3222.xcresult) |
| Mounted macOS presentation | 5 tests / 6 cases passed | [Log](/tmp/departure-decisions-hosted-macos-final2.log) |

All 108 Swift source, test, and sample files matched the recorded snapshot throughout the native validation. A later test-only cleanup explicitly discarded 19 unused internal results in `RouterTests`; it changed neither runtime source nor assertions. The macOS and both iOS package reruns after that cleanup also passed without compiler warnings; the table records those final package runs.

The subsequent map/identity/terminology/phase pass uses bounded validation rather than repeating that full UI matrix. [Focused package validation](/tmp/departure-map-decisions-focused.log) passes 75 tests across `DeclarationTests`, `RoutePhaseTests`, `SpaceAuthorityTests`, `RouteDestinationTests`, `IndependentPriorityTests`, `ScopedRouterTests`, and `UnwindPresentationPolicyTests`. [Public API grammar checks](/tmp/departure-map-typechecks.log) accept the supported composition and reject ten invalid modal-map or branch-group expressions. The [iOS sample build](/tmp/departure-map-decisions-ios-build.log) also succeeds. The earlier full native results above apply to the preceding implementation; no full UI rerun is claimed for this pass.

The preceding map/identity and cross-priority pass passed [124 focused tests in 11 suites](/tmp/departure-audit-focused-final.log), including `CrossPriorityUnwindTests`, plus [12 action/readiness tests in two suites](/tmp/departure-audit-readiness-actions.log). Coverage includes before-commit lower-space notification for native and explicit dismissal, payloads, local and cross-priority conflict barriers, combined removal, covered owner removal, elevated replacement, retained higher-space rejection, and latest live request supersession. The [final iOS sample build](/tmp/departure-audit-ios-build-final.log) succeeds. This remains focused validation; the full UI matrix has not been repeated for these changes.

The E6 change passes [61 focused tests in six suites](/tmp/departure-explicit-unwind-hooks-final.log) and the [iOS sample build](/tmp/departure-explicit-unwind-ios-build.log). Public-routing regressions cover silent ancestor crawlback and equality reuse for push, replace, sheet, and cover; high/critical root reuse and replacement; explicit notification afterward; and stale native write-back during presentation cleanup. The existing modal-stack snapshot regression now also requires no handler notification at every priority. Explicit/native timing and lower-space handoff regressions continue to pass. No full UI suite was repeated for E6.

Focused scenarios to establish next:

1. Single-group branch configuration is now covered by compiler rejection for bare `Branch`, composed/inline duplicate-group rejection, and public routing through one concurrent group. Remaining branch discovery questions belong to specification 8.
2. A modal on concurrent branch A followed by a push/select on B. Check owner `current`, local `routePhase`, action origin, and a subsequent unwind through default public routing.
3. Conflicting route types across priority catalogs are now covered by `DeclarationTests`. Extend coverage to a local declaration shadowing an elevated entry, duplicate scope IDs, and handler target IDs.
4. Covered default presentation during root reset versus whole-space removal is now covered by `CrossPriorityUnwindTests`, including latest live request supersession. Broaden native coverage at the next full UI checkpoint.
5. A reroute cycle and cancellation during that cycle. Choose one explicit failure/cancellation behavior.
6. Action reroute whose requested route is denied or superseded; deferred invocation whose original branch remains live but acquires a different current destination; repeated invocation.
7. A handler that runs before an explicit unwind is cancelled or its source becomes covered. Choose its event boundary and exactly-once identity.
8. Several explicit routing hosts for one scope, a missing declared branch in `.routing(value)`, and a selection binding containing an unknown branch value.
9. Awaited presentation with a missing host versus awaited action reroute with a missing host. Decide whether state acceptance, installation, and visibility need distinct explicit results.
10. Multiple active scenes and covered high removal while critical contains a focused text field. Verify the scene and key window, not only destination visibility.

## Suggested decision sequence

1. Command authority and source identity: owner versus scoped handle, top priority versus view-local activity, covered actions.
2. Discovery and targeting: nearest ancestor lookup, selected-branch look-forward, sibling fallback, cross-space entry catalog.
3. Intent and reuse: append, replace, existing-equivalent reuse, modal replacement, observable results.
4. Branch selection and retained state: concurrency, unknown selection, automatic reveal, root reset retention.
5. Coordination and cancellation: admission, latest-request replacement, native waits, completion guarantees.
6. Results and actions: handler origins/event timing, payload mismatch, reroute retry, invocation lifetime.
7. Invalid configuration and hosting: duplicate policy, host competition, missing bindings, supported-platform obligations.

For each agreed change, update the owning earlier specification, add the public-routing scenario, and then simplify the implementation around the new contract. A broad configurable policy object should be introduced only if these decisions reveal genuine independent consumer choices.
