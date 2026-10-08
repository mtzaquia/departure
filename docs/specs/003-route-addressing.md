# Route lookup and navigation semantics

Status: Retained behavior implemented on `zaquia/predefined-route-maps`; validation is recorded in specification 4.

Route discoverability remains exactly as it is today. The meaningful changes are predefined map declarations and typed route destinations. The map changes where definitions live and how they bind to views; it does not change which declarations a request can discover or how lookup chooses among them.

This specification records behavior to retain, not a new discoverability design. Nearest-match lookup, branch discovery and targeting, duplicate precedence, equal-route stopping, and scoped unwinding continue to work as they do in the current implementation.

Backward compatibility is not a goal. Old protocol conformances, public signatures, storage structures, helper types, and platform workaround mechanisms may be replaced or removed. The requirements below describe desired navigation outcomes rather than a mandate to reproduce the current implementation.

The intentional architectural changes already agreed in [Route maps and view bindings](001-route-map-declarations.md) and [Route destinations and context](002-route-destinations.md) still apply: definitions exist independently of views, root maps own high and critical presentations, destinations use typed builders and context, and Departure never automatically wraps destinations in stacks.

## Navigation axes

Use the following mental model for navigation state:

| Axis | Meaning | Rule |
| --- | --- | --- |
| X | Path depth | Each forward navigation advances the relevant path by one. |
| Y | Modal lane | A modal advances both X and Y by one, creating the next lane. Each lane can own at most one modal presentation. |
| Z | Branches | Branches split X into independent sub-paths. Y remains shared across all branches. |

A modal is also a forward destination in the path; creating a lane does not replace its X increment. A push within that modal advances X again while staying in the modal's lane. A nested modal advances X and creates another Y lane.

For one path, the progression can be:

| Transition | X | Y |
| --- | --- | --- |
| Root | 0 | 0 |
| Push detail | 1 | 0 |
| Present editor sheet | 2 | 1 |
| Push editor help | 3 | 1 |
| Present nested picker sheet | 4 | 2 |

The axes describe logical navigation state. They do not imply automatic `NavigationStack` construction, a new presentation API, or numeric coordinates exposed to application code.

Each priority defines its own complete X/Y/Z space. Normal, high, and critical each have independent path progression, branch paths, and modal lanes. A high-priority modal does not consume the normal space's modal capacity, and clearing one priority does not implicitly clear the others. Existing priority eligibility, blocking, and root-unwind policy coordinate operations across spaces.

These axes shape the runtime entities and their ownership, so the constraints are enforced by construction. The implemented entity model is recorded in [specification 4](004-implementation.md#ownership-of-the-xyz-navigation-space): paths project owned continuations, modal lanes own one shared slot, and each priority has its own space.

## Shared modal lanes across branches

Branches retain independent X sub-paths but do not receive independent copies of the Y modal lane. A modal presented from any branch occupies the shared modal presentation owned by that lane. Another branch cannot create a second simultaneous modal from that same lane; requests reconcile the existing shared modal using the retained presentation and unwind rules.

Navigating from inside the modal can create the next lane. Nested branch containers inside a modal likewise split their X paths while sharing that modal's Y lane. Branch selection or concurrent branch participation does not change this shared modal ownership.

The branch where a modal request originates still matters for scoped lookup and unwinding. Shared Y does not flatten branch paths or discard the request's scope identity.

## Forward navigation and unwinding

The X and Y increments apply to actual forward transitions after resolution, nearest-declaration lookup, and any required unwind. Rejected requests, equal-route reuse, and no-ops do not append a destination or increment the axes. When presenting from an earlier owner requires an unwind, advance from that owner rather than from the depth of the removed descendants.

Removing a modal unwinds its descendant path, nested lanes, and any branches owned within it. Branch paths outside that removed modal subtree remain governed by the selected unwind target. Removing or replacing content must preserve the same ownership and equality rules, including replacement-slot behavior.

Branch lifetime follows ownership of the container. Root unwind preserves inactive pushes only when the retained root itself owns the branch container. Unwinding past a descendant container removes every branch it owns, including inactive branches. A detached subtree retained for outgoing presentation is outside live navigation even while its objects and old paths still exist.

## Nearest matching declaration

Requests retain their ordinary spelling:

```swift
await router.present(ProfileRoute(userID: user.id))
```

Lookup begins at the requesting router's captured scope and follows the current eligible branch and enclosing-scope search rules. The closest eligible declaration for the requested route type wins. Reading definitions from a map must preserve the current search boundaries, precedence, and fallback behavior.

For example:

```swift
RootRouteMap {
    Sheet(Destinations.profile)

    Push(Destinations.account) {
        Push(Destinations.profile)
    }
}
```

A Profile request from Account uses Account's local push declaration. A Profile request from the root uses the root sheet declaration. Reusing the route type or destination builder does not require a public location key.

Knowing every definition in advance does not make nested declarations under unpresented destinations immediately eligible. Existing branch declaration discovery remains available, including selecting a branch whose content has not mounted. Lookup does not crawl arbitrary destination scopes in sibling stacks or construct missing ancestor route instances.

## Branch lookup

Keep explicit branch targeting:

```swift
await router.branch(AppTab.settings)
    .present(ProfileRoute(userID: user.id))
```

The branch handle selects the lookup context without changing selection merely by being obtained. Discover branch declarations even before their content mounts, activate a branch when its request is accepted, and leave selection unchanged for rejected requests. Explicit branch targeting must not silently select a sibling branch when its chosen branch has no matching declaration.

## Duplicate declarations

Within the same declaration scope, duplicate route types report a diagnostic and disable that key. A conflict stops lookup rather than falling back to another owner. This uniform route/hook policy was accepted in specification 7 and supersedes the original first-declaration-wins rule. Repeating a route type at separate scope occurrences remains valid.

Different scopes can declare the same type with different presentation styles, destination builders, or children. Their requesting scope determines precedence. Independent branches remain distinct declaration scopes.

## Internal declaration identity

Each placement in the map needs an internal identity so its presentation metadata, children, and runtime scopes refer to the correct definition. A reused `RouteDestination` value does not itself identify a unique placement. Reusing a `RouteMap` produces separate occurrences in their containing scopes.

Keep definition identity separate from domain route identity and runtime scope identity. Internal definition identity must not impose a new requirement on callers or override route equality semantics.

The earlier `RouteLocation`, declaration `id:`, and command `at:` addressing proposal is superseded. The baseline API does not require those additions for presentation disambiguation. Addressing unwind targets remains a separate capability whose new API can be designed independently.

## Equality and existing presentations

If a request matches an existing equal route eligible under its scope and presentation-owner boundaries, reuse that presentation and unwind its descendants. If it is already the relevant current route with no descendants to remove, the request is a no-op. Once equality is handled, stop rather than append another presentation.

Do not make equality a global deduplication rule across every map definition, branch, or presented instance. Equality reuse respects the requesting scope and the selected presentation path.

`Replace` keeps its existing selected-slot equality rule. An equal route pushed elsewhere does not satisfy a request to replace a slot. An equal route already occupying the selected slot retains that scope and unwinds its descendants.

## Navigation requirements

Carry forward the following navigation requirements, alongside the architectural decisions recorded in specifications 1 and 2:

- Route resolution, allow/drop/reroute behavior, and resolution of rerouted requests.
- Unwinding descendants to the matched presentation owner before appending when the requested presentation changes that path.
- Equality reuse, no-op behavior, and stopping after an equal-route unwind.
- Unwinding to the root, a branch root, a local dismissal boundary, or an identified ancestor. Root unwind clears all priorities; exact public target names remain designable.
- Scope-bound router and unwind actions, including their behavior after the originating scope leaves navigation state.
- Unwind payload delivery and scope-appropriate handlers. SwiftUI dismissals must reconcile navigation state and deliver the applicable unwind handlers.
- Independent branch X paths and concurrent participation, with Y modal lanes shared across branches and at most one modal owned per lane.
- Priority eligibility, blocking, replacement, and equality handling, under the root presentation ownership agreed in specification 1.
- Presentation readiness and coherent command completion, coordinated navigation mutations, and correct transition animations.

Source compatibility is not required, but route discoverability is outside the redesign scope. Preserve equality, unwinding, and the navigation outcomes recorded here while adapting to the map and destination architecture. Platform workarounds should be retained only where current platform behavior still requires them.

## Validation requirements

Existing discoverability tests and their expected outcomes are the baseline. Adapt setup and API spelling to maps and typed destinations while retaining search behavior. Also retain coverage for equal-route no-ops and unwinds, replacement-slot equality, unwind targets and payloads, priority behavior, and scope-bound command lifetimes. Old implementation-specific assertions need not constrain the rewrite.

Validate the axes explicitly: forward destinations advance X; modals advance X and Y; branch paths advance independently; sibling branches share modal ownership; nested modal requests create the next lane; equal or rejected requests do not advance; dismissing a modal removes its descendant lanes and paths.

Integration validation must also cover actual presentation and dismissal, because unit-level map lookup does not establish SwiftUI host readiness or animation behavior.

## Implementation integration

[Implementation architecture and simplification](004-implementation.md) describes the simpler map and accumulated-path implementation while retaining the behavior recorded here.

- How unwind targets identify predefined scopes and live ancestors.
- Reading predefined declarations using the current request-origin and discovery rules.
- Readiness and cancellation when a known declaration's required runtime presentation host is unavailable.

Navigation through unpresented ancestors or new discoverability APIs is outside the current work.
