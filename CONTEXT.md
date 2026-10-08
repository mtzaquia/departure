# Departure navigation

Departure describes navigation through path depth, modal lanes, and branches. Each presentation priority defines its own navigation space.

## Language

**Priority**:
The ordering of presentation spaces: default, high, and critical. An elevated priority is presented from the routing root.
_Avoid_: Layer

**Space**:
The complete X/Y/Z navigation state belonging to one priority. Its path, modal, and branch constraints apply independently of the other priority spaces.

**Space root**:
The starting destination or content of a space, establishing X zero and Y zero. Resetting navigation retains this root; removing the space discards it and all navigation it owns.

**Top space**:
The highest-priority space present in navigation state. It is the only space eligible to originate navigation.

**Covered space**:
A space below the top space in priority order. Its navigation is blocked while its retained paths and branches remain available when it becomes top again.

**Unwind notification**:
A before-commit callback for an explicit unwind or native dismissal, found through surviving local ancestry and then surviving lower spaces in priority order. Removal caused by presenting a route does not notify. A covered scope can receive it; its presentation attempt waits for operation completion and then rechecks coverage.

**Path (X)**:
The ordered progression of destinations leading from an owner to the current position. Each accepted forward destination advances that progression by one, including a modal destination.

**Modal lane (Y)**:
A shared modal level within a space, with capacity for one outgoing modal. That modal opens the next lane; every branch in the presenting lane shares its modal capacity.

**Branch (Z)**:
An independently retained sub-path owned by a branch container; its lifetime is bounded by that container's membership in navigation. Branches split path progression while sharing the enclosing modal lane.

**Scope**:
A particular routing position with its own definition context and enclosing navigation ancestry. A root, branch root, or live destination can establish a scope.

**Map ID**:
An explicit name for the scope receiving a map, used to target that scope during unwinding. Composition contributes definitions to a scope; it does not create another routing position.

**Live scope**:
A scope still belonging to its space's navigation tree. Being live is independent of being current or having a presentation host.

**Active scope**:
A current endpoint of a participating path within the top space and its current modal subtree. Concurrent branches can each have an active endpoint; a covered space has none.

**Route instance**:
One accepted occurrence of a route in navigation state. Its identity is distinct from route equality, declaration identity, and its current position along the axes.

**Presentation host**:
The physical view or native container that presents a scope's content. Its lifetime and readiness are distinct from the scope's membership in navigation state.

**Navigation operation**:
One accepted navigation change and its completion. Logical navigation changes when committed; outgoing presentations may finish later before a requested destination continues.

**Routing owner (`RootRouter`)**:
Owns all priority spaces and one global transition pipeline. `default` captures the default flow; `current` captures the top space.

**Scoped router (`Router`)**:
A weak handle to one live scope. It keeps that source identity across suspension and can navigate only while its space is top.

**Presentation base**:
The transparent native host installed without animation before an elevated entry animates in. It is presentation infrastructure and has no navigation coordinates.
