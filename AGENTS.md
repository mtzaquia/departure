# AGENTS.md

- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- Do not mention agents or agent tooling in commit messages, pull request titles, or pull request descriptions.
- Merge pull requests with squash merge; merge commits are not allowed for this repository.
- When drafting release notes, compare the target release against the previous tag and write in a user-facing style:
  - Group entries under `Added`, `Changed`, and `Fixed` based on user-visible behavior, not implementation mechanics.
  - Avoid internal-only details such as helper conformances, ordering used only by router internals, file renames, or test/sample-only changes unless they affect public usage.
  - Merge closely related API-surface changes into one entry instead of listing every type separately.
  - Be precise about API names and deprecation status; do not call an API deprecated unless that exact overload or symbol is deprecated.
  - Classify behavior corrections as fixes, even when they were implemented by adding infrastructure.
