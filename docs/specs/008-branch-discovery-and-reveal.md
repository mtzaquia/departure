# Branch discovery and reveal

Status: investigation and proposal. Automatic selection of a matching tab is desired. The alternative matching rules below are not accepted runtime changes.

## Intended behavior

Departure should support website-like navigation: requesting a destination can select the tab that owns it. Consumers should not have to repeat a branch address when the request already identifies an unambiguous destination in the available map.

Frame selection as revealing an accepted destination's owning branch ancestry. First resolve the route and choose its declaration occurrence, then reveal the branches needed for that occurrence. Rejected navigation must not select a tab. A reroute reveals the final matched destination, rather than the originally requested branch.

This intent replaces the suggestion in audit L4 and the opening discovery decision that crossing into a sibling should always require explicit targeting. Explicit `router.branch(...)` remains useful for choosing between genuinely ambiguous owners.

## What the implementation does today

[Scoped discovery](../../Sources/Departure/Router/RouteSpaces.swift) walks the requesting source's live ancestry. At a container, [attachment lookup](../../Sources/Departure/Router/RouteScope+Declarations.swift) prefers the selected branch's current local scope, its root definitions, the container's definitions, then inactive branch roots in declaration order. Conflicting declarations stop lookup.

[Accepted navigation](../../Sources/Departure/Router/Router+RouteDeclaration.swift) already separates matching from activation. It reveals enclosing branches through runtime ancestry; [append and reuse](../../Sources/Departure/Router/Router+Navigation.swift) activate the directly matched branch. Host readiness can defer insertion after selection. There is no need for a consumer to issue a separate tab-selection command.

The bounded investigation used public maps and presentation requests, without constructing artificial destination paths. Five temporary probe tests, including two declaration-order cases, and the existing `ScopedRouterTests` / `NestedBranchLookupTests` passed: [42 tests in three suites](/tmp/departure-branch-discovery-investigation.log). The [probe source](/tmp/Departure-BranchDiscoveryInvestigation.swift) is retained outside the package because these assertions characterize rules still under review. No runtime changes or full UI run were made for this investigation.

| Scenario | Observed result |
| --- | --- |
| A route is available in one inactive tab | The tab is selected automatically. Existing tests cover exclusive and concurrent branches, including missing hosts. |
| Home is selected; Wallet and Settings both declare the requested type | The first inactive matching branch wins. Reversing their declaration order reverses the destination owner. |
| The selected branch and the container both declare the type | The selected branch wins, including a request from the container's own router. |
| Only an inactive branch and the container declare the type | The container wins; selection stays unchanged. |
| The route is declared under Wallet → Details, with only branch roots between them | A plain request from Home does not discover it. An explicit chained branch request reaches it and selects both enclosing branches. |
| A route is declared under a destination inside another tab | Plain sibling discovery does not find it, even after that destination exists in the tab's retained history. Explicit targeting can use that tab's current scope; an absent parent destination must first be presented. |

## Recommended direction

Keep contextual nearest-match behavior and automatic branch reveal. Replace only the arbitrary choice among remaining branch candidates:

1. Walk the requesting context's existing ancestor search. At each scope, apply the agreed contextual tiers before considering that container's branch fallback. A valid contextual match determines its owner without global ambiguity checks.
2. At that fallback point, collect available matching branch-root candidates instead of returning the first declaration-order match. Keep its current position in the ancestor walk; do not collect candidates across every ancestor or priority space.
3. If one candidate remains, accept it and reveal its owning ancestry automatically.
4. If several candidates remain, diagnose ambiguity and require an explicit branch address. Reordering tabs should not silently change the owner of this request.

Uniqueness would apply to that fallback, not to the whole map. Repeated route types in separate contexts remain valid. This proposal does not require a global route registry, public declaration-occurrence keys, or a configurable lookup policy.

Investigate following nested **branch-root edges** during fallback. Those scopes already exist from the map and can be revealed by selecting their ancestors, without inventing route values. Preserve the boundary against searching arbitrary sibling destination history or descending through unpresented destination declarations. A declaration under `Push(Parent.destination)` requires a concrete parent route instance; knowing the child's type does not supply one.

The existing matching and activation split is a useful foundation. A possible simplification is for a candidate to identify the actual declaring scope and declaration, with its required branch ancestry derived from the live tree. Evaluate that against existing presentation-owner and modal-lane rules before removing the current location/anchor distinctions. Presentation and declaration ownership can differ; changing candidate discovery must not silently change unwind planning or snapshot policy.

## Decisions still open

- Whether to reject multiple inactive matching branches as ambiguous, or retain declaration order as an explicit documented tie-break. The recommendation is ambiguity rejection with the existing branch API as the escape hatch.
- Whether nested branch-root discovery should be supported automatically. The recommendation is yes, bounded by live branch roots; this expands current discovery.
- Whether the selected branch's current scope and root should continue to outrank the container's own declaration. This is a contextual precedence choice, separate from automatic reveal.
- How recursive branch-root discovery should apply those precedence tiers when an inactive branch has both a direct declaration and nested declarations for the same type.
- How a conflicting declaration in one fallback candidate affects other candidates. The current conflict barrier must not accidentally become an order-dependent bypass while collecting matches.
- How to ensure revealing several nested branches does not leave partial selection changes when an inner selection binding cannot represent its branch. Current ancestry activation writes outer selections before attempting inner ones; this needs a reachable public-routing regression before changing it.

Priority authority, delayed coverage evaluation, equality reuse, branch-path retention, shared modal lanes, and outgoing snapshots remain the existing contracts. Selection reveals an accepted destination; it does not grant authority to a covered source or infer missing parent routes.
