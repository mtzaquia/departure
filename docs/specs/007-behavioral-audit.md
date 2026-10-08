# Behavioral audit

Status: review inventory of the implementation on `zaquia/predefined-route-maps`. The descriptions below record current behavior. Recommendations are proposals, not approved behavioral changes.

This audit reopens inherited rules as well as new rules. Specifications 1–6 remain the implemented contracts until a decision here explicitly changes them. Passing tests establish the current behavior; they do not establish that a rule is desirable.

## How to review

Review one group at a time. For each rule, choose **keep**, **change**, or **remove**, then specify the consumer-visible result with a concrete example. A convenience should have one understandable default and an explicit way to express a different intent. Prefer existing explicit targets, such as `router.branch(id)`, over a collection of interacting fallback flags.

The X/Y/Z ownership constraints, consumer-facing navigation choices, and native presentation mechanics are separate review subjects. A one-modal-per-lane constraint does not by itself choose which modal a new request replaces. Exact source identity does not by itself choose whether covered requests are rejected on arrival or after a queue drains.

## First decisions

| Decision | Current rule | Initial recommendation |
| --- | --- | --- |
| Where may a plain presentation search? | Selected branch's current local scope, selected branch map, the node's own map, sibling branch maps in declaration order, then ancestors; elevated entries have a separate root-catalog fallback. | Keep nearest ancestor lookup as a documented default. Require an explicit branch target for crossing into a sibling. |
| What does route equality mean for navigation? | `Equatable` enables automatic reuse and unwinding within the matched path; replacement uses its selected slot and an elevated entry uses its own root. | Make reuse an explicit navigation contract. Ordinary data equality should not silently choose a navigation operation. Decide the default before designing its API. |
| Who may act while a space is covered? | Scoped navigation is blocked. `RootRouter` can remove covered elevated spaces. Actions can still run from live covered scopes. | Keep the explicit owner capability. Decide separately whether action execution is intentionally allowed while covered. |
| When does a queued request get rejected? | Covered and removed sources are rejected before entering the latest slot; surviving eligible requests are checked again after teardown. | Decide whether coverage should instead be checked only when buffered requests execute. Preserve exact source identity either way. |
| How are invalid declarations handled? | Duplicate routes/branches warn and keep the first; duplicate hooks warn and disable the key; missing branch bindings can silently render ordinary content. | Use one deliberate configuration-error policy. Declaration order should not resolve accidental conflicts. |
| When are unwind handlers notified? | Explicit unwinds schedule handlers before commit; native dismissal schedules them after commit; `.nearestBranch` starts lookup at the container, whereas an explicit branch-root ID starts at that branch root. | Prefer one event and one lookup origin. Preserve a distinction only if a consumer scenario requires it. |

These recommendations deliberately change some existing behavior. No corresponding runtime change is included in this audit.

## 1. Maps, route identity, and configuration

Evidence: [route builders](../../Sources/Departure/Attachments/Declarations/RouteDeclaration+Builders.swift), [compiled definitions](../../Sources/Departure/Router/RouteDefinitions.swift), [engine configuration](../../Sources/Departure/Router/RouterEngine.swift), [route protocol](../../Sources/Departure/Protocols/Route.swift), and `DeclarationTests` / `RouteDestinationTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| D1 | `RootRouteMap` supplies normal definitions and optional high/critical entry builders. Higher-priority builders accept only `Sheet` and `Cover` expressions; their children accept the full builder. | Keep the explicit modal-only origin requirement. |
| D2 | `RouteMap` composition flattens declarations into the insertion scope. It adds no runtime scope or lookup boundary. | Keep; make the distinction between composition and scope creation clear. |
| D3 | The modal-only base builders cannot directly insert an unrestricted `RouteMap`, even when that map contains only modals. Reusable modal declarations can be supplied as `Sheet`/`Cover` values; maps can compose inside their children. | Decide whether the composition restriction is the intended public contract. |
| D4 | Route and branch definitions exist independently of view installation. Runtime branch roots are created from definitions, and destination instances receive their own child definitions when inserted. | Keep as the map model's foundation. |
| D5 | The owner accepts its map once. A later `WithRouter` using the same owner does not replace its definitions; conditional map expressions are evaluated when the supplied map is constructed, not continuously reconciled into the owner. | Document static configuration, or design an explicit reconfiguration operation. |
| D6 | Declaration matching is by exact route type, independent of the route's `id` or `Equatable` value. The default route ID identifies its type; declaration IDs can override unwind-scope IDs. | Separate type lookup, public unwind IDs, value equality, and runtime instance identity explicitly. |
| D7 | The same route type can appear at different map occurrences. At one scope, duplicate route types warn and keep the first. Normal, high, and critical root declarations are concatenated into one root definition set, so the same type repeated across those catalogs also conflicts. | Review first-wins ambiguity, especially across priorities. |
| D8 | Duplicate branch values at a scope warn and keep the first subtree. Inserting the same reusable map at different occurrences compiles independent declaration occurrences. | Keep occurrence identity; review duplicate handling. |
| D9 | `Branches` uses the general route builder and checks at runtime that every expression is a branch. A `Push` inside `Branches` can therefore be a precondition failure rather than a builder-type error. | Consider making the accepted grammar explicit at compile time. |
| D10 | Destination view factories are captured by the compiled map. Environment/context values are refreshed when building the view, but changing a later map value does not replace the original factory. Hook callbacks, by contrast, refresh with their installed modifier source. | Document the lifetime of captured definitions versus live context. |

## 2. Owners, scopes, and command sources

Evidence: [RootRouter](../../Sources/Departure/Router/RootRouter.swift), [Router and origins](../../Sources/Departure/Router/Router.swift), [scope membership](../../Sources/Departure/Router/RouteScope.swift), `ScopedRouterTests`, `IndependentPriorityTests`, and `RouteOwnershipTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| O1 | `RootRouter` owns the engine. `Router` is a weak, scope-bound handle; environment defaults outside `WithRouter` are inactive. Captured routers do not keep their scopes or owners alive. | Keep exact ownership and harmless default handles. |
| O2 | `RootRouter.current` captures a source at access time. Keeping that value does not make it follow future foreground navigation. | Keep snapshot semantics; ensure naming and examples convey capture. |
| O3 | Current-scope selection follows the continuation and selected branch of the highest-priority space. Modal-lane occupancy is calculated separately. | Stress-test a modal on one concurrent branch while another branch becomes selected; define what `current` should mean. |
| O4 | A removed scope's router never falls back to a surviving ancestor or replacement instance. An outgoing retained view is already inactive for routing. | Keep; this prevents stale callbacks from redirecting navigation. |
| O5 | Navigation eligibility requires live membership in the top priority space. It does not require `routePhase == .active`. Background ancestors and unselected branches in that space may issue scoped commands. | Decide whether this is intended authority or an implicit convenience. |
| O6 | A branch router captures the owning container and an ordered branch address. It resolves that address's active local scope when a command runs; it survives dismissal of the destination that requested the handle, but not removal of its container. | Keep explicit branch targeting; distinguish it from a fixed destination handle. |
| O7 | Getting a branch handle does not select the branch. Missing or removed branch addresses are inactive; chained `branch` calls address nested branch containers and do not fall back to an ancestor's similarly named branch. | Keep no-retargeting and explicit target boundaries. |

## 3. Declaration discovery

Evidence: [scoped declaration search](../../Sources/Departure/Router/RouteSpaces.swift), [attachment ordering](../../Sources/Departure/Router/RouteScope+Declarations.swift), `NestedBranchLookupTests`, `ScopedRouterTests`, and the branch lookup cases in `RouterTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| L1 | Search begins from the requesting handle's resolved source, rather than always from the owner's global current destination. Missing matches walk backwards through that source's navigation ancestry within its space. | Keep one canonical meaning for nearest match. |
| L2 | For a plain request, a container can first discover a declaration on its selected branch's active local destination. This can win over a declaration directly on the container. | Decide whether looking forward into a selected branch belongs in nearest-node semantics. |
| L3 | At a branched node, ordinary lookup prefers the selected branch's root map, then the node's own map, then other branch root maps in declaration order. | Review selected-branch precedence and first-sibling fallback separately. |
| L4 | A sibling fallback can select that branch automatically. Reordering branch declarations can therefore change where an otherwise identical request is presented. | Prefer an explicit branch target for this intent. |
| L5 | Plain lookup does not search every sibling's deeper history or every uninstantiated descendant declaration. A branch-root map and that branch's current destination are different lookup locations. | Make the search boundary understandable; avoid calling it a search of the entire predefined tree. |
| L6 | Explicit branch handles do not use sibling-branch fallback. They can still climb to a common ancestor declaration. A reroute to such a common ancestor reveals the presentation owner's ancestry rather than the originally requested branch. | Decide whether ancestor escape is the intended meaning of an explicit branch address. |
| L7 | Space ancestry never crosses a priority boundary. After local search fails, the normal root's catalog can supply an elevated entry; normal-flow declarations cannot be found through that cross-space fallback. | Keep the explicit distinction between local definitions and the owner's entry catalog. |
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
| E6 | Automatic reuse can invoke an unwind handler for the removed source route, even though the caller asked to present a route. The retained route data/view instance is not replaced with the incoming equal value. | Make the implicit unwind and retained-value semantics explicit. |

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
| B4 | Selection writes can fail when the erased branch value cannot be represented by the binding's selection type. Such activation rejects the presentation; native binding synchronization in a covered space restores the model's retained selection. | Make configuration mismatch diagnosable and coverage rejection deliberate. |
| B5 | The public selection modifier accepts whatever value the binding currently contains. Unknown or optional empty values can leave no known branch selected; obtaining a matching explicit branch router still requires an actual declaration. | Define empty selection versus invalid selection rather than relying on incidental fallback. |
| B6 | A container's concurrency is initialized from its first branch definition. Mixed `Branches(concurrent:)` groups or direct branches in the same scope are accepted by the DSL, but later branch definitions do not choose a different container concurrency. | Code-inspection finding requiring an explicit valid-configuration rule and a focused public-routing regression. |
| B7 | An exclusive branch change can leave a presentation awaiting branch continuation. Concurrent branches can append immediately. The pending continuation can resume after a scheduled turn or host attachment; `present` does not universally mean the destination has mounted. | Keep convenience while specifying completion semantics. |
| B8 | A surviving branch host can resume an already accepted replacement while its outgoing native scopes finish. Global new requests remain buffered until operations complete. Cancelled accepted continuations cannot be revived by a host refresh. | Keep this native compatibility behavior separate from general request policy. |
| B9 | Nonmodal bindings can continue to represent unselected exclusive branch history; modal presentation drivers require branch participation. | Review whether this distinction is a presentation consequence or a consumer rule. |
| B10 | Multiple selection modifiers at one container can each update its selected value; the most recently observed binding becomes the binding used for programmatic activation. There is no duplicate-selection diagnostic. | Decide whether a container must have exactly one selection owner, rather than an update-order winner. |

## 7. Priority spaces and owner capabilities

Evidence: [spaces](../../Sources/Departure/Router/RouteSpaces.swift), [priority decisions](../../Sources/Departure/Router/Router+RouteDeclaration.swift), [owner operations](../../Sources/Departure/Router/RootRouter.swift), and `IndependentPriorityTests` / `ElevatedLifetimeTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| S1 | There is one permanent normal space and at most one high and one critical space. The highest existing space is active; lower spaces retain their own navigation state. | Keep the explicit independent-space model. |
| S2 | Present, scoped unwind, scoped whole-space removal, programmatic branch activation, and native presentation write-back reject live sources in covered spaces. A covered source cannot open a higher entry to escape the gate. | Keep one scoped navigation authority rule. |
| S3 | An eligible source in the top space can open an equal-or-higher elevated entry from the owner's catalog. A lower-priority entry request is dropped while a higher space exists. Local child declarations run within the current space. | State the entry rule independently from local presentation style. |
| S4 | The elevated entry destination is the space root. Its outer modal does not occupy a lane inside that space. Local root unwind keeps the outer modal; its root's `unwindRoute` removes the space. | Keep the explicit root distinction. |
| S5 | `Router.dismissSpace()` removes its exact top elevated space from any depth. `RootRouter.dismissSpace(priority)` can remove the addressed covered space. `dismissSpaces()` captures all currently existing elevated instances in one accepted operation. | Keep the covered removal capability on the explicit owner API. |
| S6 | Owner removal leaves other spaces intact. Absent elevated priorities, `.normal`, and plural removal with nothing to remove return `false`. A later replacement is protected from an earlier command's stale callbacks. | Keep exact-instance removal and a permanent normal root. |
| S7 | Logical removal exposes the next top space immediately, but globally buffered presentations wait for native teardown. Unequal elevated replacement installs its incoming root before awaiting the outgoing instance, so it exposes no temporary lower-space gap. | Keep atomic logical replacement and explicit completion ordering. |
| S8 | No ordinary cross-space unwind ID lookup or unwind-payload delivery exists. Whole-space owner removal has no payload overload. | Keep boundaries; add explicit cross-space results only for a real consumer need. |
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
| Q2 | The queue retains one latest eligible request. A newer queued request replaces the older and resumes its caller without presenting it. An already covered/removed source currently never enters the slot. | Decide latest attempt versus latest eligible attempt. |
| Q3 | On drain, the captured source is revalidated and the remaining resolution/declaration/equality/priority rules run against current state. A route that already finished resolution keeps that stage and is not resolved a second time. | Keep delayed evaluation and exact stage ownership. |
| Q4 | MFA removal makes the normal source eligible at logical commit; its follow-up waits for the sheet's native exit and is then evaluated without a high space. The removed MFA source cannot be used as that normal-flow source. | Keep a concrete supported handoff example. |
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
| H3 | Hooks participate only while their exact scope belongs to the live tree. Outgoing snapshots retain closures/views for teardown without retaining behavioral eligibility. Live covered scopes still have hook membership. | Keep lifetime derivation; decide covered action/notification authority separately. |
| H4 | An unwind handler is chosen for the initiating source route type, starting at the retained target and climbing its ancestors; sibling handlers and handlers merely on removed descendants do not run. Only the nearest matching handler runs. | Make bubbling and source selection explicit, or use a direct result target. |
| H5 | `.nearestBranch` deliberately starts handler lookup at the enclosing container. `.id(branchRootID)` starts at the retained branch root. Whole-space removal has no retained target and delivers no cross-space handler. | Review target-specific lookup exceptions. |
| H6 | Payload handlers require a successful cast to their payload type. A missing/mismatched payload logs and skips that selected handler; it does not search for an ancestor with a compatible payload. No-payload handlers ignore payloads. | Keep or change typed mismatch behavior deliberately. |
| H7 | Explicit accepted unwinds schedule handler work before logical commit and yield a turn; native binding dismissal commits first and schedules handlers afterward. Handlers run asynchronously and can issue requests that wait behind the operation. | Prefer a single well-defined event if consumer needs permit. |
| H8 | Delivery is deduplicated by source instance and matched target scope ID, preventing explicit unwind plus native write-back from delivering twice. A handler scheduled before commit may already run even if later cancellation/eligibility prevents commit. | Decide whether the event means accepted, committed, or completed. Review value-ID versus target-instance identity. |
| H9 | Losing live membership prevents future hook lookup and stale deferred invocation. It does not automatically cancel a handler or action body that has already begun executing across an asynchronous suspension. | State the boundary between routing authority and consumer-owned asynchronous work. |

## 11. Actions and interception

Evidence: [action API](../../Sources/Departure/Protocols/Action.swift), [action dispatch](../../Sources/Departure/Router/Router+ActionInterceptor.swift), [invocation](../../Sources/Departure/Attachments/Hooks/ActionInterceptor.swift), and `ActionHookTests` / `HookBindingTests` / `ScopedRouterTests`.

| ID | Current behavior | Review point |
| --- | --- | --- |
| A1 | `Router.perform` starts at its captured resolved source. It looks for an interceptor on that exact scope; it does not crawl ancestors for an interceptor. A branch-root action context can inherit its parent's route type. | Correct the API comment that still describes an unconditional topmost origin; decide whether inheritance is intentional. |
| A2 | A live covered scope can perform an action and use its interceptor. Navigation requested by that action remains subject to the scoped priority gate. Actions are not queued solely because a navigation operation is unfinished. | Decide whether business work should remain possible while navigation is blocked. |
| A3 | An interceptor can call, defer, suppress, or repeatedly call `invocation()`. Invocation validates that the intercepting scope is still live, then uses the original routing origin. Removal throws `CancellationError`. | Decide whether invocation is single-use and whether branch-addressed invocation should pin its exact intercepted destination. |
| A4 | Action `.reroute` schedules navigation, ends the current invocation with cancellation, waits for the selected target to install where applicable, and retries through that target's interceptor. The action retries only once. | Keep intentional forwarding, but expose what `await perform` completes. |
| A5 | The retry's destination is derived from the surviving branch/space continuation owner or the new current scope. A dropped/superseded navigation request has no structured result for the action retry to inspect. | Verify denied-route and supersession outcomes; define when retry should occur. |
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
| V7 | Detached destinations use the owner's `windowDestination` builder and captured source environment; this includes elevated presentations and UIKit normal fade covers. Consumers explicitly forward required environment values. | Keep one explicit forwarding boundary and clarify capture/refresh timing. |
| V8 | `routePhase` derives from top-space membership, branch participation, local path position, and the deepest modal subtree. Concurrent branches inside the current modal can each be active; scopes outside that modal subtree are inactive. | Document as view-local foreground state, not command authority or installation readiness. |
| V9 | Outgoing modal stacks retain pushed bindings until their modal exits. Push-only multi-unwinds clear bindings together and animate only the outermost removed push. Live bindings take precedence over outgoing projections. | Keep coherent native teardown; avoid exposing snapshot bookkeeping as API. |
| V10 | Elevated UIKit windows install a transparent base without animation before their real entry modal animates. Separate priorities have separate native windows. Sheets retain native scrim/passthrough behavior; UIKit covers use full-screen presentation. | Keep the required animation/priority mechanism as an implementation obligation. |
| V11 | On macOS, both cover transitions use sheet presentation. UIKit fade covers have a staged content fade and delayed native dismissal; slide covers use the system transition. Scene-phase changes trigger reconciliation. | Document actual platform capabilities rather than promising identical animation everywhere. |
| V12 | iOS 17 defers suspicious push nil writes until physical exit, ignores unseen-push dismissal, stages child pops before selection replacement, and uses a two-second view-exit watchdog with exact host identity. These mechanics are unavailable from iOS 18 onward. | Keep only while that platform support is required; audit observable timing separately from core rules. |
| V13 | UIKit elevated presentation uses the source host's window scene when available, otherwise the first active, inactive, or connected scene. No available scene requests route clearing. High windows use alert level minus one; critical windows use alert level. | Define scene ownership explicitly for multi-window consumers and state the limit of priority ordering. |
| V14 | Each elevated native window remembers its previous key window and restores it on teardown. This restoration is independent of the other priority window's continued visibility. | Reproduce keyboard/focus behavior when the owner removes covered high while critical remains; visibility alone does not validate key-window ownership. |

## Verification boundaries and follow-up scenarios

The operation pass validates unchanged public behavior with the package and native suites recorded in specification 6. This audit is a source-and-test inventory, not an assertion that every combination below has been reproduced on a device. Before changing a rule, add or identify a public-routing regression for its agreed replacement.

Focused scenarios to establish next:

1. A direct `Branch` followed by `Branches(concurrent: true)`, and two groups with conflicting concurrency at one scope. Choose rejection or a single declared container setting.
2. A modal on concurrent branch A followed by a push/select on B. Check owner `current`, local `routePhase`, action origin, and a subsequent unwind through normal public routing.
3. Identical route types declared in normal/high/critical catalogs; a local declaration shadowing an elevated entry; duplicate scope IDs and handler target IDs.
4. A covered normal request arriving during accepted high root reset versus whole-space removal. Choose admission timing and whether it replaces the current pending eligible request.
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
