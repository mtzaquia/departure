# Route maps and view bindings

Status: Implemented on `zaquia/predefined-route-maps`; validation is recorded in specification 4.

Departure knows its route definitions independently of mounted views. Applications declare navigation with `RootRouteMap`, and features compose reusable declarations with `RouteMap`. Views connect to that structure without defining which routes exist through their lifecycle.

Presentation declarations name domain route types. Feature-owned destination builders are supplied separately through each map's optional final `destinations:` closure, as described in [Route destinations and context](002-route-destinations.md).

## Map types

`RootRouteMap` describes one routing owner's complete navigation definition. Its primary builder accepts ordinary declarations and root-only `HighPriority` and `CriticalPriority` groups. Its optional `destinations:` builder contributes additional builders to the assembled tree.

`RouteMap` contributes declarations to its receiving scope without adding a navigation scope. Its destinations join one catalog for the complete composed tree. Repeated contributions of the same value are allowed; different destination values for one type conflict throughout the tree. The root can supply missing values, with no override precedence.

`RouteMap(id:)` optionally names that receiving scope for `.unwind(to: .id(...))`. A scope accepts one explicit ID across its root/presentation declaration and composed maps. Multiple explicit IDs report a diagnostic and disable the explicit target while retaining definitions.

`ModalRouteMap` composes sheets, covers, and other modal maps, with an optional `destinations:` builder. It can be used inside an elevated priority group. Ordinary `RouteMap` values belong in the main builder or inside an entry modal.

Priority groups are accepted only by the root builder. Neither `RouteMap` nor route children nor other priority groups accept them. A `RootRouteMap` cannot be embedded as a feature subtree.

## Root declaration

```swift
enum AppRoutes {
    static let settings = RouteMap {
        Push(AppearanceRoute.self)
        Push(AccountRoute.self) {
            Sheet(ChangePasswordRoute.self)
        }
    } destinations: {
        SettingsFeature.destinations
    }

    static let root = RootRouteMap {
        Push(ProfileRoute.self) {
            Sheet(EditProfileRoute.self)
        }
        settings
        HighPriority {
            Cover(LoginRoute.self) {
                Push(ResetPasswordRoute.self)
            }
            Sheet(MaintenanceRoute.self)
        }
        CriticalPriority {
            Cover(SessionExpiredRoute.self)
        }
    } destinations: {
        ProfileFeature.destinations
        LoginFeature.destinations
        MaintenanceFeature.destination
        SessionFeature.destination
    }
}
```

The root can contain neither priority group, either group, or both. Multiple disjoint groups compose at the root; repeated route types still conflict at their receiving scope.

## Nested declarations

`Push`, `Sheet`, `Cover`, and `Replace` accept a route type, an optional scope ID, and an optional child declaration builder. `Cover` also accepts its transition. They do not accept destination values, inline view builders, `priority:`, or `providesNavigation:`.

```swift
Push(ProfileRoute.self) {
    Sheet(EditProfileRoute.self) {
        Push(AvatarPickerRoute.self)
    }
}
```

Sibling declarations belong to the same scope. A child builder describes navigation available within each presented instance of its parent route. It does not present the child or create a navigation stack.

The same route type may occur in different scopes with different presentation styles and children, sharing one destination binding throughout their routing owner. Each placement has a distinct declaration identity. Reusing a map retains separate placements and runtime state while preserving nearest eligible declaration lookup.

## Root presentation priorities

`HighPriority` and `CriticalPriority` accept only sheets, covers, and modal maps at their base. Entries present from the routing root above ordinary navigation. Their children describe local navigation within that priority space; a nested push or sheet inherits the entry's effective priority without becoming another root entry.

A high-space source can request a root-declared critical entry while eligible. The owner presents an independent critical space. Nested priority groups are rejected at compile time. Replacing, dismissing, and resolving competing root presentations follow the runtime routing specification.

## Router installation

The `routes:` parameter of `WithRouter` accepts only `RootRouteMap`. A reusable `RouteMap` must be composed into a root map before installation.

```swift
WithRouter(routes: AppRoutes.root) {
    AppView()
}
```

Backward compatibility with existing initializers is not required. An optional `router:` argument preserves an explicit routing handle. A `windowDestination:` trailing closure customizes detached presentation content and receives its source environment.

## View bindings

`WithRouter` automatically annotates and wires its root content for the root map. Departure also automatically annotates and wires each presented destination for that route's definition. Ordinary content therefore does not need to repeat a routing modifier solely to establish its scope.

The public view binding surface has three forms:

| Modifier | Responsibility |
| --- | --- |
| `.routing()` | Connect presentation at this view to the current mapped scope. |
| `.routing(AppTab.home)` | Annotate and wire branch content for the matching `Branch` in the current mapped scope. |
| `.routing(branch: $tab)` | Connect presentation at the branch container and its selection binding to the current mapped scope. |

A receiving scope accepts exactly one `Branches` group across its containing and composed maps. `Branch` expressions are accepted only inside that group. Concurrency belongs to the group, rather than individual branches or view bindings. Multiple groups diagnose and disable the branch container while retaining sibling routes.

The container's selected value belongs to the model. A mounted container accepts exactly one external selection owner through `.routing(branch:)`; multiple owners diagnose and disable selection changes until one remains. An unmounted container retains its model selection and mapped discoverability. Selection callbacks belong to the existing routing attachment and leave with that attachment. Branch values must be representable by the binding's selection type; an incompatible activation diagnoses the types and leaves navigation unchanged.

The branch-value form replaces the proposed `.routeBranch` spelling. The binding form applies to the container, while the value form applies to each branch's content. Neither form contributes declarations to the map.

The unqualified modifier uses the current scope; it does not create another one. A branch-value modifier connects to a mapped child branch scope. Repeated wiring for the same scope must not create duplicate route scopes or competing presentation owners. Exact host reconciliation is an implementation concern.

An explicit `.routing()` or `.routing(branch: binding)` takes presentation ownership over automatic wiring at the same scope. Use it inside a custom container to capture environment values applied there. The binding form also synchronizes branch selection, so it needs no additional `.routing()`. This changes physical host placement without adding a logical scope.

Routing is independent of `NavigationStack`. A view can host sheets, covers, or replacement content without providing stack navigation. `.routing()` does not create a stack, and a branch does not imply one either.

## Explicit navigation stacks

For pushes, application code creates a native `NavigationStack` and applies `.routing()` to its root content inside the stack:

```swift
NavigationStack {
    HomeView()
        .routing()
}
```

Automatic root or destination wiring establishes the scope, while `.routing()` inside the stack connects presentation at the appropriate location. It does not create a second scope. Departure provides no navigation-stack wrapper.

Departure never automatically wraps root content or a presented destination in a navigation stack. Automatic routing annotation only connects the view to its mapped scope and presentation machinery. The destination itself decides whether to construct a `NavigationStack` with `.routing()` on its root content, another container, or no navigation container.

For example, a sheet with nested push declarations supplies its stack explicitly in the destination:

```swift
// In the destination builder for EditProfileRoute:
NavigationStack {
    EditProfileView()
        .routing()
}
```

Nested `Push` declarations do not cause Departure to infer or create a stack. Application code supplies both the stack and its root's routing modifier.

## Branched scopes

`Branches` groups the named child scopes of a branch container. Its `BranchDeclarationBuilder` accepts only `Branch` expressions, including conditional and loop-generated branches. Other route declarations are siblings of the group in the enclosing map. Each `Branch` has its own declarations and navigation state within an instance of the owning scope. `RouteMap` composition remains transparent: inserting a reusable map within a branch contributes declarations to that branch rather than creating another scope.

Branches split the X path into independent sub-paths while sharing the Y modal lane. They do not create independent modal presentation capacity. Each lane can own at most one modal, which creates the next lane. The complete X/Y/Z mental model is recorded in [Route lookup and navigation semantics](003-route-addressing.md).

```swift
static let root = RootRouteMap {
    Sheet(HelpRoute.self)

    Branches {
        Branch(AppTab.home) {
            home
        }

        Branch(AppTab.settings) {
            settings
        }
    }
}
```

Declarations outside `Branches` belong to the containing scope. Declarations inside a `Branch` belong to that branch's child scope. Nested route builders can declare their own `Branches`, allowing branch containers within presented destinations. Branch values are interpreted within their owning mapped scope, so different containers can reuse the same values.

The view connects the container and its content separately:

```swift
WithRouter(routes: AppRoutes.root) {
    TabView(selection: $tab) {
        NavigationStack {
            HomeView()
                .routing()
        }
        .routing(AppTab.home)
        .tag(AppTab.home)

        SettingsView()
            .routing(AppTab.settings)
            .tag(AppTab.settings)
    }
    .routing(branch: $tab)
}
```

The example deliberately gives only Home a navigation stack. Each branch's map must match the presentation capabilities of its view hierarchy; the Settings branch can use modal or replacement navigation without a stack.

Branch definitions are known before their content mounts. The view binding connects a live host to the corresponding logical branch scope; it does not discover or define that scope. Unmounting a host must not remove branch definitions. Runtime state retention and presentation readiness are specified separately.

`Branches(concurrent: true)` declares that its branches participate together, as in a split view. The ordinary form uses exclusive participation, as in a tab container. This setting belongs to the map and stays the same when a split view collapses. The selection binding connects the container's selected or preferred branch; changing it does not redefine the map. Branch discovery and targeting retain their current behavior as recorded in specification 3.

## Definition lifetime

The complete definition is available to the router independently of whether destination views or branch views have mounted. Registering or removing a live view may change which presentation hosts are available; it must not install or remove the route definitions themselves.

Knowing a nested definition does not by itself construct missing ancestor route instances or expand lookup eligibility. Retain current discoverability. Navigation through unpresented ancestors and new deep-link path APIs are outside the current scope.

[Implementation architecture and simplification](004-implementation.md) specifies persistent definitions and accumulated view path contexts. View bindings project state without installing declarations through lifecycle callbacks.

## Related contracts and deferred work

- Specification 3 records branch activation, discoverability, shared modal arbitration, priorities, and unwind behavior.
- Specification 4 records readiness, snapshots, binding ownership, and the implemented simplification.
- Builders support conditionals, optional groups, and arrays. Elevated root builders accept modal declarations and reject top-level branches, pushes, and replacements.
- Additional physical presentation hosts or replacement slots in one mapped scope, runtime map replacement, and recursive definition references remain outside this API.

### Elevated entry builder constraint (2026-10-13)

`RootRouteDeclarationBuilder` accepts root-only `HighPriority` and `CriticalPriority` groups. Their `ModalRouteDeclarationBuilder` accepts sheets, covers, and modal maps. Pushes, replacements, branches, and ordinary maps belong inside an entry's child builder. Unsupported or nested priority groups fail at compile time. The entry modal is the logical root of its priority space.
