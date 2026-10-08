# Departure design specifications

These specifications record the map rewrite implemented on `zaquia/predefined-route-maps`. The usage guides in `docs/` and the sample use this API. Specification 4 records the simplification inventory and validation evidence, including the implemented X/Y/Z entities and canonical host lifecycle. [The domain glossary](../../CONTEXT.md) defines the navigation terms.

[Specification 5](005-independent-priority-spaces.md) records independent space roots and explicit owner coordination. The implementation and combined native validation are complete; its validation section records the final checks.

[Specification 6](006-navigation-operations.md) records operation-owned transition coordination and the removal of separate transaction tokens, append wait records, and global snapshot identities.

[Specification 7](007-behavioral-audit.md) inventories current explicit and implicit behavior, recommendations for review, and scenarios that need focused verification before changing their contracts.

This work may be a full rewrite. Backward compatibility, migration shims, and retention of old implementation structures are not requirements. Carry forward the navigation principles and runtime lessons recorded here, and evaluate the new design against those deliberate requirements.

The implemented redesign focuses on predefined map declarations and typed route destinations. Specification 3 records the discovery behavior retained during that rewrite. Specification 7 reopens inherited and new behavioral rules for review; its recommendations become contracts only after an explicit decision updates the owning specification.

Keep each specification focused on one major part of the design. Record agreed contracts separately from open questions, and update the relevant specification when a decision changes.

## Specifications

1. [Route maps and view bindings](001-route-map-declarations.md) — root maps, reusable subtrees, nested declarations, root presentation priorities, routing modifiers, and branched scopes.
2. [Route destinations and context](002-route-destinations.md) — typed destination values, domain and feature ownership, scoped actions, presentation information, and environment forwarding.
3. [Route lookup and navigation semantics](003-route-addressing.md) — X path depth, shared Y modal lanes, Z branches, unchanged discoverability, equality, and unwinding.
4. [Implementation architecture and simplification](004-implementation.md) — persistent definitions, accumulated view paths, binding projections, unwind plans, snapshots, and removal of declaration lifecycle machinery.
5. [Independent priority spaces](005-independent-priority-spaces.md) — actual space roots, local root reset, navigation originating only from the top space, and explicit owner-level dismissal.
6. [Navigation operations](006-navigation-operations.md) — one owner for each transition's plan, outgoing projections, native waits, and pending presentation, with global request sequencing.
7. [Behavioral audit](007-behavioral-audit.md) — discovery, equality, command authority, branches, priorities, unwinds, resolution, buffering, hooks, actions, configuration errors, and native hosting, with open decisions separated from current behavior.
8. [Branch discovery and reveal](008-branch-discovery-and-reveal.md) — investigation of automatic tab selection, ambiguous branch matches, nested branch roots, and a proposed bounded matching rule.
