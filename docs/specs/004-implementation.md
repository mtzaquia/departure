# Implementation architecture and simplification

Status: The map rewrite, X/Y/Z ownership model, canonical host lifecycle, and ARC ownership fix are implemented on `zaquia/predefined-route-maps`. The inventory and validation below describe the implementation.

The rewrite must drastically simplify Departure by removing view-lifecycle-driven route declaration management. The predefined map is the persistent source of route definitions. Views inherit and extend the path leading to their own scope, and presentation bindings project navigation state from that path.

Keep the navigation behavior recorded in [specification 3](003-route-addressing.md), including discoverability, equality, unwinding, modal ownership, and branch boundaries. Unwind plans, transition snapshots, and presentation readiness still serve real purposes. They must work with the simpler architecture without recreating the old declaration installation machinery.

Backward compatibility and preservation of current internal types are not goals. Specifications [1](001-route-map-declarations.md) and [2](002-route-destinations.md) define the new map, destination, and view binding surface.

## Core architecture

Use three conceptual parts, with one routing owner coordinating them:

| Part | Responsibility |
| --- | --- |
| Definition map | Persistent declaration structure, destination builders, branch definitions, presentation styles, and root priorities. |
| Navigation state | Live route instances, scope identities, branch sub-paths, shared modal lanes, selections, and presentation ownership. |
| View projections | An accumulated path context, presentation bindings, destination construction, and environment forwarding. |

Keep transition plans, snapshots, and any necessary host-readiness coordination alongside navigation state. A snapshot is temporary presentation data for a transition; it is not another independently mutable navigation graph.

Do not flatten navigation into one global array. Runtime state must represent X path depth, Y modal lanes shared across branches, and Z branch sub-paths. A view's path is the prefix for its own position in that structure.

The concrete storage can use values, references, or a combination. Choose the smallest representation that supports stable instance identity and the required projections; existing `RouteScope`, `RouteTree`, `RouteForest`, and ledger shapes are not constraints.

## Ownership of the X/Y/Z navigation space

Implemented on 2026-10-06, with ARC ownership corrected on 2026-10-08: each priority owns a `RouteSpace`. `RouteScope` strongly owns its X continuation, including modal destinations, its mapped branch roots, and its child `RouteLane`. Each lane tracks one optional modal destination through a weak occupancy reference validated against live topology. `RoutePath` is a read-only projection through X ownership; it stores no destination array. Structural ownership enforces capacity and membership without a coordinate cache.

The following entities are internal; they do not add public API requirements:

| Entity | Ownership and constraint |
| --- | --- |
| Space | Belongs to exactly one priority and owns its initial modal lane. Normal, high, and critical have independent X/Y/Z state. |
| Modal lane (Y) | Tracks one optional outgoing modal transition without owning it. That transition opens exactly one child lane in the same space. |
| Path (X) | Owns the ordered forward progression at its routing position. A modal extends the accumulated path by one and continues it in the child lane. |
| Branch container (Z) | Owns ordered, independent branch paths and selection/participation. Its branch paths all use the enclosing lane's single modal capacity. Nested containers establish their own branch identities. |
| Scope / route instance | Has one structural location and stable instance identity, with its matched definition and accumulated enclosing context. Coordinates are derived from that location. |

The unbranched path and every nested branch container in a lane share the same outgoing modal slot. Opening a modal creates a new lane; branches inside that modal share the new lane. A branch cannot allocate another modal slot for its current lane.

The modal instance is represented once. Its contribution to X and the continuation into Y are projections of the same owned transition, not independently mutable copies in a path array and a modal registry. A modal opened after an X-depth of two is the destination at X three, Y one; pushing inside it reaches X four, Y one. Branching at either position forks X while retaining that position's lane.

Topology mutation goes through the owning entities. Every root or branch has exactly one canonical path. Append checks the destination and vacant continuation/modal slot before changing ownership. Presentation metadata is fixed before a destination enters live navigation. Trim cuts the retained position’s single X ownership edge. Every removed container takes all its branches with it; their paths stay intact only while outgoing owners retain them. The unwind plan enumerates those descendants for snapshots and completion without recursively mutating their paths. There is no independently writable `x`, `y`, or `z`, and a scope cannot be appended into another priority's space or registered in two branch paths. X/Y/Z describes location; instance identity continues to protect captured commands and native callbacks when positions are reused.

Priority ordering remains a router policy across spaces. Each space enforces its own topology constraints. A destination opened locally inside the high space remains in that space even when its mapped declaration is an ordinary push or modal. Root-owned elevated presentations retain their existing definition lookup and root-environment forwarding; lookup context across priorities does not become structural ownership across spaces.

Unwind plans operate on the owned structure: removing a modal removes its child lane and descendants; trimming one branch affects its X path and any modal transition owned by a removed position. Other branch paths and other priority spaces remain subject to the selected unwind policy. The initial implementation used the cross-priority root-unwind behavior in specification 3. Specification 5 supersedes that behavior with space-local reset and explicit whole-space removal.

The implementation eliminates modal-depth scans, discovery of competing modals across branch arrays, and repeated reconstruction of space/path membership. Predecessor and owning-path references locate a route directly; its links to the current root establish live membership. Root-unwind modal cleanup follows the lane chain while retaining the existing inactive-branch policy. The predefined map remains immutable. Nearest-match lookup, equality reuse, replacement-slot equality, payload delivery, snapshots, and native readiness retain their behavioral contracts.

## Canonical host lifecycle

A scope's logical location and its physical presentation host are separate facts. Logical membership is derived from the space's owned structure. Physical ownership and readiness are derived from the canonical host record. An outgoing scope may already have left live navigation state while its native host is still completing dismissal.

Root, destination, and branch views report one host event carrying the exact scope and host identity. Views must not separately mutate the managed anchor, signal scope installation/removal, resume pending requests, and trigger native reconciliation. The canonical operation applies the event, then performs the effects of the accepted state change once.

For example, the former paired calls:

```swift
router.root.ledger.uninstallManagedView(id: lifecycleID)
router.routeScopeDidLeaveView(router.root)
```

are replaced by one identity-checked operation:

```swift
router.hostDidDetach(router.root, id: lifecycleID)
```

There is no separate ledger. The scope owns the accepted host identity and weak native anchor; readiness is derived from that record. The engine applies accepted events and their routing effects once. A late callback from a replaced host cannot remove the current anchor or mark the replacement unready. Repeating detachment has no additional effect. The same contract applies to attachment, environment refresh, and platform-specific reconciliation.

| Fact or effect | Canonical source |
| --- | --- |
| Scope belongs to live navigation | Its location in the owning space. |
| Host ownership and current readiness | The accepted host identity and native anchor. |
| Selected routing projection and source environment | The ordered host registrations and existing explicit-host precedence. |
| Captured live hooks | Their own accepted host registrations, independent of definitions. |
| Installation/teardown waiters and pending branch resumption | Changes in the accepted readiness state. |
| Platform reconciliation and priority cleanup | The accepted event and identity of the corresponding route instance. |

Derive current values from these facts and publish only the changes consumers need. Preserve genuine history where required, such as whether a push has ever appeared for the iOS 17 workaround, and continuations for asynchronous completion. A transient bridge replacement still does not remove logical branch state, erase definitions, or discard an accepted hook registration merely because an anchor is temporarily unavailable.

The host record replaces paired bookkeeping and notification paths. `hostDidAttach` handles readiness, attachment reconciliation, iOS 17 reconciliation, and pending branch resumption. `hostDidDetach` validates identity before native reconciliation, waiter completion, or priority cleanup. The iOS 17 watchdog captures the host identity it is waiting for; it cannot detach a later replacement.

Validate the entity model with public routing through two branches sharing one modal lane, nested modals, independent priority spaces, equal-route reuse, and branch-specific unwinding. Validate host attachment, replacement followed by stale detachment, duplicate events, and waiter completion through the same canonical event path. Retain native integration checks for outgoing nested stacks, branch bridge replacement, and unmanaged presentation isolation.

## Persistent definitions

Compile and normalize the complete root map when its routing owner is initialized, including every route child and branch subtree. Associate every declaration occurrence with its destination builder and compiled children. Compose reusable maps without introducing artificial scopes.

All runtime instances of one declaration occurrence share its immutable `RouteDefinitions` node. Each instance creates its own branch scopes, selections, and paths. Repeated composition of the same feature map creates distinct declaration occurrences, while repeatedly presenting one occurrence does not recompile it.

Definition structure stays stable for that owner's lifetime. SwiftUI reevaluating a body does not reinstall the map. Runtime replacement of the complete map is outside the current scope.

No appearance, disappearance, deinitialization, native view ownership check, branch host installation, or presentation callback may add or remove a route definition. Rebuilding a view or replacing a native bridge must not change declaration precedence or discoverability.

Definition knowledge and lookup eligibility remain separate. The router knows all definitions but searches them using the existing request-origin, branch, ancestor, and priority rules. An unpresented parent still does not supply a live parent scope or its route data.

## Accumulated path context

Each view inherits the path leading to it. At a logical routing boundary, derive an extended context from that prefix and pass it to descendants through the environment. Ordinary view composition carries the context unchanged.

The internal context needs enough information to identify:

- The routing owner and current runtime scope instance.
- The corresponding definition occurrence.
- The enclosing path and branch ancestry.
- Modal presentation ownership and current priority.

These are logical references, not an array of mounted views. Stable runtime scope identities are required: a stale callback must not address a new route merely because it occupies the same array index or path depth.

The public modifiers follow the contracts already agreed:

| Boundary | Context operation |
| --- | --- |
| `WithRouter` | Seed the root context and wire root presentation. |
| Presented destination | Extend to the committed destination instance and its definition. |
| `.routing()` | Use the inherited context and install presentation projections at this view. Do not append another logical scope. |
| `.routing(branchValue)` | Enter the mapped child branch scope for the current owner instance. |
| `.routing(branch: binding)` | Connect container selection to the owning branch state. Do not create definitions or another scope. |
| `RoutedNavigationStack` | Create the explicitly requested stack and apply the same unqualified routing projection to its root content. |

Logical route and branch state belongs to the routing owner. A view does not construct a second mutable branch graph in `@State` and register it after mounting. Branch state can be initialized from its owning runtime scope and the map, independently of native host installation.

Snapshot-rendered destinations retain the context for their outgoing instance. A captured router or unwind action remains bound to that instance even after the live path changes.

## Discoverability from the accumulated path

Resolve a request using the map, current navigation state, and its captured origin context. Search the nearest eligible definition scope and follow the unchanged discoverability rules from specification 3.

The accumulated prefix supplies scope and ancestor information that currently has to be recovered from installed declaration sources. It must not enable a new global search or change branch targeting boundaries. Same-scope duplicate handling follows the later accepted conflict policy in specification 7.

Matching a declaration does not wait for that declaration to be installed by a view. Waiting may still be needed for the corresponding presentation host to become ready after a branch selection or another transition.

## Binding projections

Bindings read the presentation belonging to their accumulated context and presentation role. They use the live navigation state, or the applicable outgoing snapshot during a transition, to produce the item or path that SwiftUI displays.

Binding getters do not install declarations, mutate navigation state, or change scope identity. Presentation identity comes from the runtime instance, independently of route type equality and definition identity.

Each physical presentation must have one effective owner. Repeating `.routing()` for the same scope must not create competing modal bindings or replacement owners. Use the context and presentation role to identify ownership; retain a small stable host token only where physical host identity is necessary. Do not recreate a stack of declaration sources to solve host placement.

Shared Y modal ownership is projected consistently by branch hosts. A branch must not gain its own modal capacity merely because it has its own path prefix. Normal-priority local presentation uses its appropriate host; high and critical root presentation uses the router root. One resolver projects both local and root presentations, and one binding implementation validates the expected destination instance before accepting write-back. Each root priority has one detached host that chooses sheet, slide, or fade presentation from the committed destination snapshot. Native style-specific adapters retain their own transition behavior.

SwiftUI write-back is a navigation event, not permission to truncate an arbitrary array. A pop, sheet dismissal, cover dismissal, or replacement removal must be interpreted against the expected presentation instance and fed through the router's unwind machinery.

Late or duplicate write-back from an outgoing host must not dismiss its replacement, remove a different branch's path, or restore a removed route. Validate instance ownership and transition identity before accepting it.

## Unwind plans and transitions

Keep one authoritative transition pipeline. Route resolution and nearest-declaration lookup determine the transition, including equality reuse or a no-op. Compute the unwind plan before committing mutations.

The plan identifies retained and removed runtime scopes across paths, shared modal lanes, branches, and priorities. Apply the same plan to state changes, payload delivery, outgoing presentation data, and animation decisions. View modifiers must not independently reconstruct competing unwind decisions.

`commitTransition` captures outgoing presentation records before applying that plan. `finishTransition` waits for native teardown and releases the matching snapshot. Explicit unwind, route replacement, equality reuse, and binding write-back use these common stages. Preserve their event timing: native dismissal commits synchronously; explicit unwind delivers hooks before commit; an append waiting for a modal releases its snapshot before waiting for the inner pushed scopes that the snapshot keeps alive.

An append after unwinding begins from the selected presentation owner. Equality reuse unwinds the relevant descendants and stops. Replacement equality remains specific to its selected slot.

Coordinated requests must revalidate their captured origin after asynchronous resolution or waiting. Superseded or cancelled work cannot append into an obsolete scope or complete a different transition.

## Transition snapshots

Retain snapshots only for presentation data that must outlive its removal from live navigation state. They preserve the outgoing destination, its scope identity, environment, and required binding projections until the corresponding transition can finish.

A snapshot stores records keyed by presentation host identity and style. Each record retains its outgoing host and resolved presentation, plus whether the binding must survive and whether its pop animation is suppressed. It stores no copied forest, copied path arrays, or duplicate global policy sets. The authoritative unwind plan may still contain preserved path data while constructing those records.

In particular, dismissing a modal containing pushed destinations must not tear down its inner stack's bindings prematurely. Preserve the outgoing stack for that dismissal. A push-only unwind must coalesce into the intended visible pop rather than separately animate every removed descendant.

A binding consults a snapshot only when that snapshot applies to its outgoing instance and presentation role. Snapshot data cannot participate in live lookup, reactivate a removed scope, or become a second declaration source.

Associate each snapshot with its transition. Clearing an older snapshot must not clear a newer one. Release preserved projections at the stage that allows native teardown to finish; never wait for a view to disappear while keeping it alive through the same snapshot. Completion, supersession, and cancellation must release the snapshot and finish the appropriate waiters.

## Minimal presentation lifecycle

View lifecycle can still report genuine presentation readiness, completed dismissal, environment capture, or platform-host cleanup. Keep that tracking separate from map definition and discoverability.

Use the smallest event-driven coordination needed to meet binding and command-completion requirements. Do not add arbitrary delays, polling, forced declaration reinstalls, or a readiness state machine that duplicates navigation state.

Any remaining platform bridge or workaround must have a concrete presentation responsibility and validation on supported platforms. A temporary native bridge replacement must not remove a logical path or erase its definitions. Removing a logical destination is a navigation-state mutation, not an inference from transient view disappearance.

Scoped hooks and unwind handlers may still need live registrations or captured closures. Their lifetime handling must not reinstall route definitions or reinstate the old all-purpose ledger; the hook surface can be designed separately.

## Destination context and environment

Construct `RouteContext` from the matched definition, runtime scope, and the environment at destination evaluation. Its router and unwind action use the accumulated scope context. Its presentation style and priority describe that actual instance.

Local destinations inherit their presentation host's environment. Continue detached-host forwarding and customization, sourcing high and critical root presentations from the root environment. Build the public context with the same effective values that the destination receives.

Environment observation and refresh do not alter definition structure. Route destinations never cause automatic stack wrapping; explicit container construction remains application code's choice.

## Machinery to remove

The simplification must remove the responsibilities below, not move them unchanged into renamed abstractions:

| Current machinery | New expectation |
| --- | --- |
| Route declaration install, uninstall, prepare, commit, and source reconciliation | One persistent definition map with direct lookup. |
| Ordered route-source stacks and restoring a previous source on teardown | No lifecycle-owned route sources to replace or restore. |
| Route declaration attachments and native ancestry checks authorizing their installation | Path-derived scope context; definitions require no native ownership authorization. |
| Environment accumulation and branch adoption of discovery-only declarations | Direct access to the mapped branch definition. |
| View-created branch scopes registered into the declaration graph after mounting | Logical branch state owned by navigation state; views project that state. |
| Declaration changes triggering graph mutations during SwiftUI lifecycle updates | Rendering reads definitions and state without reinstalling either. |
| `Route`/`RouteViewProviding` dispatch precedence and fallback destinations | The one typed destination builder bound to the declaration. |
| Presentation metadata controlling automatic navigation wrapping | Destinations explicitly construct their containers. |

`RouteScopeLedger` is deleted. `RouteScopeAttachment` retains only the native ownership gate for physical routing hosts and captured hooks. Definitions require no attachment or native ownership authorization. Host facts live on the scope; derived readiness and selected routing host are the only observed physical projections.

Lookup rules, plans, snapshots, native presentation adapters, and required host coordination may survive in substantially smaller forms. Their behavior matters; their current type names and storage do not.

## Acceptance criteria

- The router resolves eligible definitions from a root map without mounting destination or branch views.
- View mounting and teardown never add, remove, or reorder route definitions.
- Root, destination, and branch contexts derive from an accumulated path with stable runtime instance identities.
- Branch X paths remain independent and all branches share the appropriate Y modal lane.
- Binding write-back, equality, payloads, and dismissals use the same authoritative transition and unwind decisions.
- Outgoing snapshots preserve required bindings and release without deadlocking teardown or accepting stale callbacks.
- High and critical detached hosts forward environment values from the root, with matching values in destination context.
- The production implementation materially reduces registration state, lifecycle-driven graph mutation, and the number of coordinating mechanisms. Renaming or splitting the old machinery is insufficient.

Provide a before-and-after inventory of removed responsibilities and remaining stateful mechanisms. Explain each retained lifecycle or native-host dependency in terms of a presentation behavior that requires it. Line count is supporting evidence, not the sole measure of simplification.

## Validation

Use focused model tests for unchanged discoverability, equal-route stopping, unwind planning, shared modal ownership, branch independence, and snapshot projection. Test lookup before any views mount, stale instance write-back, superseded requests, and snapshot cleanup at the appropriate teardown stage.

Use actual platform integration to verify stack pops, modal dismissal with nested pushes, replacing a modal from another branch, nested modal lanes, concurrent split branches, and detached environment forwarding. Include explicit stacks and destinations with no stack. UI rebuilds and temporary host replacement must not affect definition availability.

Prototype the smallest complete root to push to sheet to nested-push flow, then branch-shared modal behavior, before broadening the implementation. This validates the new path and binding model early. No current implementation complexity should be carried forward without a demonstrated requirement.

## Implemented simplification inventory

Compared with the branch's starting commit, production Swift source decreases from 10,502 to 8,360 lines: 2,142 fewer lines (20.4%), including the new API and ARC fix. The X/Y/Z and canonical host pass reached 8,344 lines from the preceding 8,403-line implementation; the ARC correction removes recursive cleanup while adding non-owning routing context and complete outgoing-subtree planning. Most of this pass's simplification is removing duplicate storage and graph reconstruction, rather than a large net reduction in source. Counts include blank lines and license headers; tests, examples, and guides are excluded.

| Removed responsibility | Resulting implementation |
| --- | --- |
| Route-source prepare, commit, install, uninstall, restore, and reconciliation | The owner compiles the complete map once. Route instances share immutable compiled child definitions and create only their own runtime branch state. |
| View-created branch scopes and branch registration restoration | The owning runtime scope creates ordered mapped branch scopes before any host mounts. |
| Parent-side copies of branch declarations and adoption of environment discovery declarations | Lookup reads each mapped scope's own definitions. |
| Rematching declarations after asynchronous presentation waits | A request retains the matched occurrence and revalidates its runtime scope. |
| Elevated presentation dependencies on requesting scopes | High and critical flows belong to the root and survive lower navigation independently. |
| Separate append construction for local and elevated routes | One committed destination construction path attaches definition, environment, and effective priority. |
| Repeated reconstruction of path membership, predecessor, and modal depth | Owned links identify the path, predecessor, and shared lane directly. Ordered branch enumeration remains for unwind policy and presentation projection. |
| Destination-provider dispatch, missing-destination fallback, and automatic stack flags | Every declaration carries one typed destination builder; application views choose containers. |
| Separate local/elevated binding resolvers and write-back paths | One presentation target, resolver, and binding implementation projects live state or the applicable outgoing record. |
| Six sheet/slide/fade priority hosts | Two root hosts, one per elevated priority, select the native presenter from the committed snapshot. |
| Forest and path copies plus duplicate snapshot policy sets | Direct outgoing presentation records carry binding retention and animation decisions. |
| Parallel append, explicit unwind, and native dismissal completion machinery | Shared transition commit and completion stages preserve the required timing of each entry point. |
| Duplicate elevated origin, hook declaration cache, and captured unwind handler | Scope presentation metadata holds origin/environment; view hook sources are the sole hook store, with matches derived by identity and constrained to live scopes; captured unwind actions use scoped `Router`. |
| Equivalent-route helper duplication, map identity, and manual hash boilerplate | One reuse helper, one owner configuration flag, and synthesized hashing where field identity is sufficient. |
| Separate scope ledger and paired host bookkeeping/signals | One accepted scope host record and one engine event; stale and duplicate detachments have no effects. |
| Independently writable path arrays and modal-depth arbitration | Read-only X path projection; every Y lane tracks one live modal instance, shared by its Z branches. X owns the modal’s lifetime. |
| Cached active scope ID and post-mutation reconciliation signal | Active position is derived from the current space and observed branch/topology facts. Branch binding refreshes notify only when selection or concurrency changes. |

`RouteScopeLedger` is deleted. `RouteScope` owns the necessary native host fact, ordered routing registrations, live captured hooks, environment reference, and asynchronous waiters. Installed readiness and selected presentation host are derived. There is no separately mutable installed flag or selected-host cache. `RouteScopeAttachment` binds a hook or physical routing host to an exact scope; it cannot mutate mapped branch membership.

The remaining stateful mechanisms have specific behavioral purposes:

| Mechanism | Behavior requiring it |
| --- | --- |
| Priority spaces, scope continuations, lane modal slots, and ordered branches | Stable route-instance identity, independent branch paths, shared modal lanes, and independent root priorities. |
| Unwind plans and navigation transactions | Consistent equality reuse, payload delivery, cancellation, supersession, and command completion. |
| Outgoing presentation snapshots | Keep nested pushed content intact while its enclosing modal dismisses; suppress redundant descendant pop animation. |
| Routing host tokens | Choose one physical owner per scope; explicit container bindings take precedence over automatic bindings. |
| Native managed-view anchors and readiness continuations | Wait for selected presentation hosts and completed native dismissal; prevent unmanaged sheets from stealing the originating scope's hooks or bindings. |
| Hook-source ordering | Preserve live captured closures and restore enclosing hooks when a nested hook host leaves. |
| iOS 17 stack workaround | Reconcile native branch stack pops and allow subsequent pushes on the supported older OS. |
| Detached window adapters and source environment | Present elevated priorities and fade covers with the agreed environment forwarding. |

Physical bookkeeping is excluded from SwiftUI observation. Only selected host identity and readiness are observed: native lifecycle callbacks must not invalidate their own bridges while updating token or hook registries. Each route instance stores effective priority so outgoing context remains correct after its live priority space is removed.

## Initial map validation completed on 2026-10-05

| Platform | Result |
| --- | --- |
| macOS package tests | 274 tests in 17 suites passed. |
| macOS hosted presentation tests | All 6 tests passed, including inline replacement without a stack, contextual branch replacement, unmanaged-sheet isolation, and both elevated fade priorities. |
| iOS 27 package tests | 268 tests in 16 suites passed, including UIKit ownership and physical branch-host rebinding. |
| iOS 17.5 package tests | 268 tests in 16 suites passed with the native stack workaround enabled. |
| iPhone, iOS 27 | 15 distinct selected UI tests passed after the final simplification pass. |
| iPad, iOS 27 | Both selected UI tests passed: concurrent split branches and replacement preserving other columns. |
| iPhone, iOS 17.5 | All 3 selected UI tests passed: native Back followed by re-push, replacement clearing descendants, and root unwind preserving two pushes inside a sheet. |

The final iOS 27 UI checks cover root, ancestor, and binding sheet dismissal; nested sheets and stacks; normal/high/critical equivalent-route retention; native Back and re-push; shared-lane modal replacement; inline replacement; cross-style elevated replacement and continuation; critical presentation above high priority; sheet passthrough and scrim isolation; and fade-cover navigation. The modal replacement check also verifies its presentation host's custom environment value. Earlier map-rewrite checks additionally exercised branch bridge replacement, modal chaining, concurrent branch covers, and local navigation inside elevated flows.

Package tests cover immutable definitions before mounting, definitions shared across instances with independent branch state, distinct occurrences when composing a feature map twice, nearest-match and explicit-branch boundaries, inactive captured routers, payloads and hooks, stale binding write-back, cancellation, pending branch readiness, unwind plans, and outgoing context priority.

One iOS 17 fixture initially attempted to dismiss a push that had never appeared. The existing workaround intentionally ignores that callback. The fixture now models an appeared destination leaving its native host, and the full suite passes with the workaround retained.

Tests use the package workspace (`.swiftpm/xcode/package.xcworkspace`, scheme `Departure`) for iOS package coverage, and `SampleApp.xcodeproj`, scheme `SampleAppUITests`, for native sample interactions. `swift test` runs package tests on macOS; `DEPARTURE_RUN_HOSTED_UI_TESTS=1 swift test --filter MacOSPresentationTests` enables hosted macOS checks. The sample and usage guides have been migrated to the map API. `git diff --check` passes.

That initial pass used selected native regressions. The X/Y/Z pass below extends validation to the full iPhone UI suite.


## X/Y/Z and canonical host validation on 2026-10-06

The full macOS package run passes 282 tests in 18 suites. All six mounted macOS presentation tests pass. The final iOS 27 and iOS 17.5 package runs each pass 276 tests, including UIKit host ownership and branch rebinding.

The full SampleApp UI suite on iPhone/iOS 27 passes 37 tests, with the two iPad-only tests skipped. After removing the cached active-scope signal, five focused tests pass again: branch activation and stack persistence, tab bridge replacement, concurrent branch targeting, native Back and re-push, and route phase. Both iPad-specific tests also pass: concurrent split branches and replacement preserving other columns.

All three final iPhone/iOS 17.5 native checks pass: native Back followed by re-push, replacement clearing descendant navigation without adding a back entry, and root unwind retaining two pushes inside the outgoing sheet.

New model coverage verifies X progression through nested modals, shared Y slots across independent Z paths, independent priority coordinates, immutable presentation metadata, inactive captured scopes, accepted host replacement, stale/duplicate detachment, readiness waiter completion, and observations derived from branch state. iOS 17 watchdog tests verify that an old deadline cannot detach a replacement while retaining the missing-callback fallback for that replacement.

These 2026-10-06 results predate specification 5. Its entry-as-root model, local root unwind, and stricter covered-space gates are now implemented; the combined validation is recorded there.

## ARC ownership audit on 2026-10-06 (resolved below)

Public-routing scenarios confirm the correct branch invariant: a branched root retains its inactive sibling pushes, but removing a nested container makes every branch it owns inaccessible to live lookup and captured commands. Retained outgoing objects need not have empty paths. A weak-reference test confirms that an ordinary detached container, both of its branches, and their pushed destinations release through ARC when outgoing owners let go. No manual branch cascade is required for that topology.

The audit identified two obstacles to relying on ARC throughout the model:

- The shared `RouteLane` strongly owns its modal. Detaching a branch container without planner-specific modal cleanup leaves that modal retained by an ancestor lane, outside the discarded subtree. Its lifetime ownership therefore crosses the branch boundary.
- `RouteSourceEnvironment` stores environment values that can contain the same `RouteScope`. A weak-reference probe confirms that this creates a self-retaining cycle even after every external scope reference is released.

At that point, root planning also missed an inactive nested branch in its outgoing scope/snapshot set when the container is removed from an active branch of a branched root. Live membership already rejects that detached branch, but transition effects still depend on per-request branch enumeration.

The next ownership revision should make every forward destination, including a modal, strongly owned by its preceding X position. Shared Y capacity should use a non-owning occupancy reference validated against live topology, and backward/context references should remain non-owning. Stored source environments must not create ownership cycles through routing values. Snapshots deliberately retain detached outgoing subtrees until native completion; ARC then releases them. Planning enumerates affected subtrees for snapshots, handlers, and readiness, rather than maintaining a second lifetime system by recursively clearing branch paths.

At the time of this audit, the modal/environment ownership changes were findings and proposed work. The isolated lifetime probes and their failing results are saved outside the test target in `/tmp/departure-arc-investigation-tests.swift` and `/tmp/departure-arc-ownership-audit.log`. Permanent `RouteSpaceTests` cover branch membership, preservation at a branched root, inactive captured commands, and ARC release of ordinary detached branch subtrees.

The full macOS package run with those permanent ownership regressions passes 285 tests in 18 suites. No production source changed during this audit; the modal and source-environment probes remain evidence for the next ownership revision, rather than claimed fixes.


## ARC ownership fix on 2026-10-08

The ownership changes identified by the audit are implemented. X is the strong forward ownership chain for every destination, including modals. Z containers strongly own their branch roots. Y occupancy and backward/context references are non-owning. A lane validates its weak occupant against live X/Z topology, so an outgoing snapshot cannot keep a modal slot occupied after the owner is detached. Observations of modal occupancy invalidate when that structural owning edge is cut.

Stored routing environments use weak scope and engine references, and the routers and unwind actions injected into them reference the engine without owning it. Source environments still retain application environment values for forwarding. An explicitly created `RootRouter()` and `WithRouter` retain their engine as the routing owner. The internal environment property wrapper waits until SwiftUI supplies its dynamic environment before requiring the owner, allowing ordinary view initialization with an empty default environment.

A path trim cuts one edge and leaves the outgoing subtree intact. The canonical unwind plan drops redundant descendant trims and captures every owned branch path, including inactive descendants of a removed container, for snapshot projection and completion. This fixes the branched-root outgoing-record omission. Surviving root-owned inactive branch pushes continue to follow the existing reset policy; a removed nested container and all of its branches become inaccessible immediately.

Permanent regressions cover release of detached modal and ordinary branch subtrees, release after the outgoing snapshot is dropped, availability of the shared lane while that snapshot is retained, occupancy observation, inactive nested-branch records, and release of an engine and scope despite retained source environments and scoped actions. Older assertions about empty detached paths now assert absence from live routing. The iOS 17 replacement-host fallback test awaits actual completion instead of assuming it happens within a fixed wall-clock interval.

The 2026-10-06 audit results above are historical evidence. This section records the ownership fix before the separate priority semantics and owner API in specification 5 were implemented.


### Validation of the ownership fix

| Final code check | Result |
| --- | --- |
| macOS package suite | 290 tests in 19 suites passed. |
| Mounted macOS presentation suite | All 6 tests passed. |
| iOS 27 package suite | All 284 tests passed. |
| iOS 17.5 package suite | All 284 tests passed. |
| Full iPhone/iOS 27 SampleApp UI suite | 37 passed; the 2 iPad-only cases were skipped as expected. |
| iPad/iOS 27 UI cases | Both iPad-only cases passed, completing all 39 UI cases across iPhone and iPad. |
| iPhone/iOS 17.5 native regressions | All 3 passed: Back/re-push, replacement, and root unwind preserving the outgoing sheet stack. |

Production and sample source remained unchanged throughout these ownership-fix checks. They predate the priority semantics in specification 5; that specification records the combined implementation and its validation.
