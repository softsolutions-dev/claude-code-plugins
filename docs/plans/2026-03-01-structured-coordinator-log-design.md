# Structured Coordinator Log

## Problem

Coordinator log entries are freeform plain text lines. After compaction, 30 dense lines get injected — hard to scan, wastes context tokens. The coordinator mixes "what happened" with detail in a single blob.

## Design

### Storage: JSONL

One JSON object per line in `.sessions/{sessionId}.log` (same path, new format).

```jsonl
{"ts":"2026-03-01T16:10:58Z","goal":1,"title":"Designer APPROVED Task #12","description":"Clean diff, all checks pass, matches workout detail pattern."}
{"ts":"2026-03-01T16:20:15Z","goal":1,"title":"Task #12 done, commit c3ccaea"}
```

Fields:
- `ts` — ISO timestamp, auto-injected by server
- `goal` — active goal ID, auto-injected by server (null if no active goal)
- `title` — short summary, provided by coordinator
- `description` — optional detail, provided by coordinator

### Write: `coordinator_log_write({title, description?})`

Coordinator provides title + optional description. Server auto-attaches `ts` and `goal` (from active goal in goals file). Appends one JSONL line.

### Read: `coordinator_log_read({lines?, all_goals?})`

- Default: entries matching current active goal, last 15
- `all_goals: true`: all entries regardless of goal
- **Tiered output**: last 5 entries as `[time] title — description`, entries 6-15 as `[time] title` only
- Goal ID stripped — coordinator never sees it

### Injection (reinject-context.sh)

Same as `coordinator_log_read` default — current goal entries, 5 full + 10 title-only. Replaces current "last 30 raw lines."

### CLI (`agile-team`)

Parse JSONL. Optional `--goal N` filter.

### Goal scoping

- Goal ID is internal metadata — never exposed to coordinator
- Default reads are scoped to current active goal
- Entries with `goal: null` (written when no goal active) only visible via `all_goals: true`
- `all_goals: true` is the escape hatch for cross-goal context

## Changes

| Component | Change |
|---|---|
| `coordinator-log.js` | JSONL write, goal-filtered tiered read |
| `reinject-context.sh` | Parse JSONL, 5+10 tiered formatting |
| `coordinator-context.md` | Update tool instructions for title/description |
| `tools/agile-cli` | Parse JSONL format |

## Migration

Hard break. Old plain text `.log` files are dead — won't render in new system.
