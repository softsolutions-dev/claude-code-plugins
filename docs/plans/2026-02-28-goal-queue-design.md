# Goal Queue System — Design Document

## Problem

The agile team works best with a single goal but struggles with multiple goals:
- Coordinator tries to parallelize, assigns tasks from different goals simultaneously
- BA/Tech Lead break down all goals upfront, creating an undifferentiated task list
- Context compaction causes later goals to disappear
- Developers mix concerns across goals
- Visible future work creates psychological pressure to rush current goal

Research confirms this is not just behavioral — it's structural:
- LLMs degrade exponentially with multiple simultaneous instructions (Curse of Instructions)
- Future goals in context consume attention tokens and actively degrade current task quality (Lost in the Middle, Context Rot)
- Microsoft's CORPGEN: agents halve completion rate when exposed to cross-task context
- Kanban WIP limits yield +40% throughput, -60% delivery time
- Zeigarnik Effect: visible unfinished tasks reduce productivity by up to 40%

## Design

### Core Principle

**One goal at a time. Future goals are invisible to the team.**

The coordinator manages the goal queue. The team only ever sees the current active goal. Goals are broken down (by BA/Tech Lead) only when they become active — never upfront. This enforces focus structurally, not behaviorally.

### MCP Tools

Extend the existing `coordinator-log` MCP server with three new tools:

| Tool | Input | Returns |
|------|-------|---------|
| `goal_add` | `{ description: string }` | `"Added goal 3: Improve onboarding"` |
| `goal_current` | `{}` | `"Goal 2 of 4: Fix settings bug"` or `"All goals complete"` |
| `goal_complete` | `{}` | `"Goal 2 complete. Now active — Goal 3 of 4: Fix settings bug"` or `"All 4 goals complete."` |

Design choices:
- **No `goal_list`** — coordinator cannot see the full queue
- **No `goal_skip`** — cannot jump ahead
- **No `goal_reorder`** — sequence is locked
- Structurally impossible to rush — the tools don't allow it

### Storage

Goals stored as structured JSON at `.sessions/{session_id}.goals.json`:

```json
{
  "goals": [
    { "id": 1, "description": "Add dark mode", "status": "completed" },
    { "id": 2, "description": "Fix settings bug", "status": "active" },
    { "id": 3, "description": "Improve onboarding", "status": "pending" }
  ]
}
```

`session_id` injected by the existing PreToolUse hook (extend matcher to include `goal_` tools).

### Context Injection

`reinject-context.sh` updated to also inject the active goal after compaction:

```
## Active Goal
Goal 2 of 3: Fix settings bug
```

Only the active goal and position shown — no other goals exposed.

### Goal Lifecycle

1. User runs `/agile-team add dark mode, fix settings, improve onboarding`
2. Coordinator spawns all teammates
3. Coordinator reads user input, creates goals via `goal_add` in priority order
4. Coordinator calls `goal_current` — gets first goal
5. BA/Tech Lead break down **only this goal** into tasks
6. Team works it through full lifecycle (implement → test → review → commit)
7. All gates pass → coordinator calls `goal_complete`
8. Clean slate — next goal surfaces, BA/Tech Lead decompose it fresh
9. Repeat until all goals complete

### Coordinator Context Updates

Add to `coordinator-context.md`:
- Goals are the unit of delivery. Create them first, then work them sequentially.
- Only break down the active goal. Future goals are invisible — do not plan, decompose, or discuss them.
- Call `goal_complete` only when all gates have passed.
- On all goals complete: summarize accomplishments, ask user if there's more.

### End-of-Session Flow

When `goal_complete` returns "All goals complete":
1. Coordinator writes summary to coordinator log
2. Presents report: what was accomplished per goal
3. Asks user if there are more goals to add

### Hook Changes

Extend PreToolUse hook matcher from `.*coordinator_log.*` to `.*coordinator_log.*|.*goal_.*` to inject `session_id` into goal tools.

## What This Does NOT Include

- Goal dependencies or ordering logic (goals are worked in insertion order)
- Goal editing or removal (keep it simple — add and advance)
- Priority changes mid-session
- Cross-goal context carryover (clean slate by design)
