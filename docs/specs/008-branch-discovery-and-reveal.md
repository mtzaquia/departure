# Branch discovery and reveal

Status: current discovery consolidated with its existing rules retained. Automatic selection of a matching tab is desired. The alternative matching rules below remain proposals and are not accepted runtime changes.

## Intended behavior

Departure should support website-like navigation: requesting a destination can select the tab that owns it. Consumers should not have to repeat a branch address when the request already identifies an unambiguous destination in the available map.

Frame selection as revealing an accepted destination's owning branch ancestry. First resolve the route and choose its declaration occurrence, then reveal the branches needed for that occurrence. Rejected navigation must not select a tab. A reroute reveals the final matched destination, rather than the originally requested branch.

This intent replaces the suggestion in audit L4 and the opening discovery decision that crossing into a sibling should always require explicit targeting. Explicit `router.branch(...)` remains useful for choosing between genuinely ambiguous owners.

## What the implementation does today

[Ordered discovery](../../Sources/Departure/Router/RouteSpaces.swift) walks the requesting source's live ancestry. At a container, it prefers the selected branch's current local scope, its root definitions, the container's definitions, then inactive branch roots in declaration order. Conflicting declarations stop lookup.

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

The existing matching and activation split remains the foundation. The consolidation below derives branch association from the live tree while preserving distinct presentation and container anchors. Proposed changes to candidate discovery must not silently change unwind planning or snapshot policy.

## Decisions still open

- Whether to reject multiple inactive matching branches as ambiguous, or retain declaration order as an explicit documented tie-break. The recommendation is ambiguity rejection with the existing branch API as the escape hatch.
- Whether nested branch-root discovery should be supported automatically. The recommendation is yes, bounded by live branch roots; this expands current discovery.
- Whether the selected branch's current scope and root should continue to outrank the container's own declaration. This is a contextual precedence choice, separate from automatic reveal.
- How recursive branch-root discovery should apply those precedence tiers when an inactive branch has both a direct declaration and nested declarations for the same type.
- How a conflicting declaration in one fallback candidate affects other candidates. The current conflict barrier must not accidentally become an order-dependent bypass while collecting matches.
- How to ensure revealing several nested branches does not leave partial selection changes when an inner selection binding cannot represent its branch. Current ancestry activation writes outer selections before attempting inner ones; this needs a reachable public-routing regression before changing it.

Priority authority, delayed coverage evaluation, equality reuse, branch-path retention, shared modal lanes, and outgoing snapshots remain the existing contracts. Selection reveals an accepted destination; it does not grant authority to a covered source or infer missing parent routes.

## Ordered resolver consolidation on 2026-10-08

One ordered resolver reads each candidate's immutable definitions and constructs the resolved target once. The separate ancestry lookup and branch attachment helpers, including the helper that rebuilt an existing match, are removed. Selected-destination look-forward, selected-root precedence, container precedence, declaration-order sibling fallback, explicit branch boundaries, and conflict stopping retain their existing order. Root-owned elevated entries use the same definition resolver with selected-destination look-forward disabled; they remain a separate fallback across space boundaries.

The target retains both its presentation anchor and enclosing declaration/container anchor. A push declared at a branch root can discard that branch's current detail; a push declared on that detail retains it. In both cases discovery through an enclosing modal can remove the enclosing modal without discarding unrelated branch history. The target's branch association derives from its presentation anchor's ancestry relative to its container anchor, rather than storing another branch ID. Enclosing selections still validate together, while the final branch activation and host wait remain at their existing staging boundary.

The resolver adds no persistent state, registry, route-address API, or scope. Equality, unwind plans, outgoing snapshots, source authority, and native readiness still operate after discovery. This pass removes **30 net production Swift lines**. Tests that inspected the removed helpers now inspect compiled definitions or the canonical resolver; no test-only lookup wrapper is retained.

Public-routing regressions verify both push anchors behind an enclosing modal and a selected destination inside nested branches. The latter retains its exact detail while resolving its outer container and branch correctly. These scenarios use `RootRouter`, `WithRouter`, and public presentation requests without synthesizing destination paths.

Validation: **255 package tests in 15 affected suites passed**, and the optimized Release build passed. Evidence: `/tmp/departure-ordered-resolver-focused-final.log` and `/tmp/departure-ordered-resolver-release.log`.

All **five mounted macOS tests** passed, including both elevated fade priorities. Four unchanged iOS 27 UI cases passed for ancestor push replacement, automatic branch crawl and stack persistence, tab-host replacement, and split-column targeting/local dismissal. Both unchanged iOS 17.5 cases passed for automatic branch crawl and native Back/re-push. These are focused checks; the complete UI suite was not repeated after the preceding beta checkpoint. No resolver or UI-test source changed during the final native checks.

Evidence: `/tmp/departure-ordered-resolver-mounted-macos.log`, `/tmp/departure-ordered-resolver-native-27.log`, and `/tmp/departure-ordered-resolver-native-17.log`. XcodeBuildMCP bundles are `test_sim_2026-10-08T20-12-30-902Z_pid99910_f8046b9c.xcresult` (iOS 27) and `test_sim_2026-10-08T20-17-18-822Z_pid3694_0f20af2c.xcresult` (iOS 17.5).
