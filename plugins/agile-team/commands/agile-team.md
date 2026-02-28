---
name: agile-team
description: Create an agile team of agents to work on a task
---

<!-- AGILE_TEAM_ACTIVATED -->

Create an agile team of agents to: $ARGUMENTS

Your first action is to spawn ALL teammates below. The full team must exist before any work begins. Then create goals from the user's request via `goal_add` and call `goal_current` to start the first one.

@${CLAUDE_PLUGIN_ROOT}/context/coordinator-context.md
