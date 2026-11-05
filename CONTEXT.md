# Departure navigation

Departure describes one navigation tree through path depth, modal lanes, and branches. Global declarations share destinations across that tree; dismissal protection applies only to active route instances.

## Language

**Navigation tree**:
The complete navigation state owned by one routing owner, including its application root, paths, modal lanes, and branches.

**Application root**:
The permanent starting content of a navigation tree. Resetting navigation retains this root.

**Unwind notification**:
A before-commit callback for an explicit unwind or native dismissal, found through surviving navigation ancestry. Removal caused by presenting a route does not notify; follow-up requests recheck current dismissal protection.

**Path (X)**:
The ordered progression of destinations leading from an owner to the current position. Each accepted forward destination advances that progression by one, including a modal destination.

**Modal lane (Y)**:
A shared modal level within a navigation tree, with capacity for one outgoing modal. That modal opens the next lane; every branch in the presenting lane shares its modal capacity.

**Branch (Z)**:
An independently retained sub-path owned by a branch container; its lifetime is bounded by that container's membership in navigation. Branches split path progression while sharing the enclosing modal lane.

**Branch container**:
One `Branches` group at a mapped scope. Compiled definitions own its concurrency setting; runtime state owns one selected value. Its mounted view may connect exactly one selection binding owner. Composition contributes to the receiving scope and cannot add a second container there.

**Scope**:
A particular routing position with its own definition context and enclosing navigation ancestry. An application root, branch root, or live destination can establish a scope.

**Map ID**:
An explicit name for the scope receiving a map, used to target that scope during unwinding. Composition contributes definitions to a scope; it does not create another routing position.

**Route declaration**:
One placement of a route type in a map, describing its presentation and the navigation available from that destination. Its identity is distinct from a route instance and route equality.

**Destination builder**:
The feature-owned construction of a view from typed route data and the destination's routing context. It is independent of where the route is declared.

**Destination binding**:
The association between a route declaration and the one destination value for its route type in the composed root tree. Multiple maps may contribute the same value; distinct values for one type conflict.

**Live scope**:
A scope still belonging to its owner's navigation tree. Being live is independent of being current or having a presentation host.

**Active scope**:
A current endpoint of a participating path within the current modal subtree. Concurrent branches can each have an active endpoint.

**Route instance**:
One accepted occurrence of a route in navigation state. Its identity is distinct from route equality, declaration identity, and its current position along the axes.

**Presentation host**:
The physical view or native container that presents a scope's content. Its lifetime and readiness are distinct from the scope's membership in navigation state.

**Resolved route target**:
A matched declaration, its declaring owner, the scope that presents it, and any required branch selection. The scope identities determine its paths and coordinates.

**Navigation operation**:
One accepted navigation change and its completion. Logical navigation changes when committed; outgoing presentations may finish later before a requested destination continues.

**Routing owner (`RootRouter`)**:
Owns one navigation tree and its transition pipeline. `root` captures the permanent application root; `current` captures the foreground scope.

**Scoped router (`Router`)**:
A weak handle to one live scope. It keeps that source identity across suspension; requests respect effective dismissal protection.

**Global route**:
A route declared in a global map and available throughout a routing owner's navigation, including while another route has effective dismissal protection.

**Global map**:
A root-declared collection of globally available route declarations. Its entries have individual presentation styles and may individually declare dismissal protection.

**Dismissal protection**:
A declaration's restriction against routing requests that incidentally remove its active route instance. It stops applying while the route is inactive and resumes if that instance becomes active again. The destination owns its interactive dismissal behavior; native dismissal is reconciled with navigation state.
