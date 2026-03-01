# Structured Coordinator Log — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace freeform plain text coordinator log with structured JSONL entries, auto-timestamped and goal-scoped, with tiered injection (5 full + 10 title-only).

**Architecture:** JSONL file (one JSON object per line) replaces plain text. MCP server auto-attaches `ts` and `goal` fields. Read/injection defaults to current-goal entries only. Coordinator sees `title`/`description` — never sees `goal` field.

**Tech Stack:** Node.js (MCP server), bash + jq (hooks), TypeScript (CLI)

---

### Task 1: Update `coordinator_log_write` in MCP server

**Files:**
- Modify: `plugins/agile-team/servers/coordinator-log.js`

**Step 1: Update tool schema**

In the `TOOLS` array, replace the `coordinator_log_write` definition:

```javascript
{
  name: 'coordinator_log_write',
  description: 'Append a timestamped entry to the coordinator log. This is your persistent memory — it survives context compaction.',
  inputSchema: {
    type: 'object',
    properties: {
      title: { type: 'string', description: 'Short summary of what happened' },
      description: { type: 'string', description: 'Optional detail (findings, decisions, context)' }
    },
    required: ['title']
  }
}
```

**Step 2: Update write handler**

Replace the `coordinator_log_write` handler block:

```javascript
if (name === 'coordinator_log_write') {
  if (!args.title) {
    return respond(id, { content: [{ type: 'text', text: 'Error: title is required' }], isError: true });
  }
  try {
    fs.mkdirSync(SESSIONS_DIR, { recursive: true });
    const ts = new Date().toISOString();

    // Auto-attach active goal
    const goalsData = readGoals(sessionId);
    const activeGoal = goalsData.goals.find(g => g.status === 'active');

    const entry = { ts, goal: activeGoal ? activeGoal.id : null, title: args.title };
    if (args.description) entry.description = args.description;

    fs.appendFileSync(logPath, JSON.stringify(entry) + '\n');
    respond(id, { content: [{ type: 'text', text: `Logged: ${args.title}` }] });
  } catch (e) {
    respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
  }
}
```

**Step 3: Verify**

Create a test JSONL file manually and confirm format:
```bash
echo '{"ts":"2026-03-01T16:00:00Z","goal":1,"title":"Test entry","description":"Some detail"}' > /tmp/test.jsonl
cat /tmp/test.jsonl | jq .
```

**Step 4: Commit**

```bash
git add plugins/agile-team/servers/coordinator-log.js
git commit -m "feat: coordinator_log_write outputs JSONL with auto timestamp and goal"
```

---

### Task 2: Update `coordinator_log_read` in MCP server

**Files:**
- Modify: `plugins/agile-team/servers/coordinator-log.js`

**Step 1: Update tool schema**

Replace the `coordinator_log_read` definition in the `TOOLS` array:

```javascript
{
  name: 'coordinator_log_read',
  description: 'Read the coordinator log. Returns last 15 entries for the current goal by default. Last 5 entries include full detail, entries 6-15 are title-only.',
  inputSchema: {
    type: 'object',
    properties: {
      lines: { type: 'number', description: 'Number of entries to return (default 15)' },
      all_goals: { type: 'boolean', description: 'Include entries from all goals, not just current (default false)' }
    }
  }
}
```

**Step 2: Update read handler**

Replace the `coordinator_log_read` handler block:

```javascript
else if (name === 'coordinator_log_read') {
  try {
    if (!fs.existsSync(logPath)) {
      return respond(id, { content: [{ type: 'text', text: '(log is empty — no entries yet)' }] });
    }

    const rawLines = fs.readFileSync(logPath, 'utf-8').split('\n').filter(l => l.trim());
    let entries = [];
    for (const line of rawLines) {
      try { entries.push(JSON.parse(line)); } catch { /* skip non-JSON lines */ }
    }

    // Filter by current goal unless all_goals requested
    if (!args.all_goals) {
      const goalsData = readGoals(sessionId);
      const activeGoal = goalsData.goals.find(g => g.status === 'active');
      if (activeGoal) {
        entries = entries.filter(e => e.goal === activeGoal.id);
      }
    }

    const limit = args.lines || 15;
    const tail = entries.slice(-limit);

    if (tail.length === 0) {
      return respond(id, { content: [{ type: 'text', text: '(no entries for current goal)' }] });
    }

    // Tiered output: last 5 full, rest title-only
    const formatted = tail.map((e, i) => {
      const ts = e.ts.replace('T', ' ').replace(/\.\d+Z$/, 'Z');
      const fromEnd = tail.length - i;
      if (fromEnd <= 5 && e.description) {
        return `[${ts}] ${e.title} — ${e.description}`;
      }
      return `[${ts}] ${e.title}`;
    });

    respond(id, { content: [{ type: 'text', text: formatted.join('\n') }] });
  } catch (e) {
    respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
  }
}
```

**Step 3: Commit**

```bash
git add plugins/agile-team/servers/coordinator-log.js
git commit -m "feat: coordinator_log_read with goal filtering and tiered output"
```

---

### Task 3: Update `activate-mode.sh` for JSONL session start

**Files:**
- Modify: `plugins/agile-team/hooks/activate-mode.sh`

**Step 1: Replace plain text session marker with JSONL entry**

Change line 15 from:
```bash
echo "--- Session started $(date -u +%Y-%m-%dT%H:%M:%SZ) ---" >> "$SESSION_LOG"
```
to:
```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"goal\":null,\"title\":\"Session started\"}" >> "$SESSION_LOG"
```

**Step 2: Verify**

```bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"goal\":null,\"title\":\"Session started\"}" | jq .
```

Should output valid JSON with ts, goal: null, title: "Session started".

**Step 3: Commit**

```bash
git add plugins/agile-team/hooks/activate-mode.sh
git commit -m "feat: activate-mode writes JSONL session start entry"
```

---

### Task 4: Update `reinject-context.sh` for JSONL tiered injection

**Files:**
- Modify: `plugins/agile-team/hooks/reinject-context.sh`

**Step 1: Replace `tail -30` with JSONL-aware tiered formatting**

Replace the last section of the script (the log output section):

```bash
echo ""
echo "## Coordinator Log (last 30 lines — use coordinator_log_read for full history)"
echo ""
tail -30 "$SESSION_LOG"
```

with:

```bash
echo ""
echo "## Coordinator Log (last 15 entries — use coordinator_log_read for full history)"
echo ""

# Parse JSONL, filter by active goal, format tiered (5 full + 10 title-only)
if [ -f "$SESSION_LOG" ]; then
  GOAL_FILTER="null"
  if [ -n "$GOAL_ID" ]; then
    GOAL_FILTER="$GOAL_ID"
  fi

  jq -rs --argjson goal "$GOAL_FILTER" '
    [ .[] | if $goal != null then select(.goal == $goal) else . end ] |
    .[-15:] |
    . as $tail |
    ($tail | length) as $total |
    range($total) |
    . as $i |
    ($total - $i) as $from_end |
    $tail[$i] |
    (.ts | sub("T"; " ") | sub("\\.[0-9]*Z$"; "Z")) as $ts |
    if $from_end <= 5 and .description then
      "[\($ts)] \(.title) — \(.description)"
    else
      "[\($ts)] \(.title)"
    end
  ' "$SESSION_LOG" 2>/dev/null
fi
```

Note: `$GOAL_ID` is already extracted earlier in the script (used for the active goal section). Reuse it here.

**Step 2: Verify jq pipeline independently**

Create a test JSONL file and run the jq command against it:
```bash
cat > /tmp/test-log.jsonl << 'EOF'
{"ts":"2026-03-01T16:00:00.000Z","goal":1,"title":"Entry 1","description":"Detail 1"}
{"ts":"2026-03-01T16:01:00.000Z","goal":1,"title":"Entry 2"}
{"ts":"2026-03-01T16:02:00.000Z","goal":2,"title":"Entry for goal 2"}
{"ts":"2026-03-01T16:03:00.000Z","goal":1,"title":"Entry 3","description":"Detail 3"}
{"ts":"2026-03-01T16:04:00.000Z","goal":1,"title":"Entry 4"}
{"ts":"2026-03-01T16:05:00.000Z","goal":1,"title":"Entry 5","description":"Detail 5"}
{"ts":"2026-03-01T16:06:00.000Z","goal":1,"title":"Entry 6","description":"Detail 6"}
{"ts":"2026-03-01T16:07:00.000Z","goal":1,"title":"Entry 7","description":"Detail 7"}
EOF

jq -rs --argjson goal 1 '
  [ .[] | select(.goal == $goal) ] |
  .[-15:] |
  . as $tail |
  ($tail | length) as $total |
  range($total) |
  . as $i |
  ($total - $i) as $from_end |
  $tail[$i] |
  (.ts | sub("T"; " ") | sub("\\.[0-9]*Z$"; "Z")) as $ts |
  if $from_end <= 5 and .description then
    "[\($ts)] \(.title) — \(.description)"
  else
    "[\($ts)] \(.title)"
  end
' /tmp/test-log.jsonl
```

Expected: 7 entries for goal 1. Entries 1-2 title-only, entries 3-7 full (last 5). Goal 2 entry filtered out.

**Step 3: Commit**

```bash
git add plugins/agile-team/hooks/reinject-context.sh
git commit -m "feat: reinject-context parses JSONL with goal filtering and tiered output"
```

---

### Task 5: Update `coordinator-context.md` with new tool interface

**Files:**
- Modify: `plugins/agile-team/context/coordinator-context.md`

**Step 1: Update the "Coordinator Log" section**

Replace:
```markdown
## Coordinator Log

Maintain a running log using `coordinator_log_write`. This is your persistent memory — it survives context compaction. Append after every significant event: decisions, task completions, gate results, blockers, user feedback, key state changes. Be concise — write entries so a future you can pick up exactly where you left off.

Use `coordinator_log_read` to review your history (returns last 50 lines by default).
```

With:
```markdown
## Coordinator Log

Maintain a running log using `coordinator_log_write`. This is your persistent memory — it survives context compaction.

Each entry has a **title** (short summary) and optional **description** (detail). Timestamp and goal tracking are automatic.

```
coordinator_log_write({ title: "Task #12 done, commit c3ccaea" })
coordinator_log_write({ title: "Designer APPROVED screenshots", description: "8/8 pass. Minor note on spacing — non-blocking." })
```

Log after every significant event: decisions, task completions, gate results, blockers, user feedback. Title should be scannable — a future you reading just the titles should know what happened.

Use `coordinator_log_read` to review history (returns last 15 entries for current goal). Use `coordinator_log_read({ all_goals: true })` to see entries across all goals.
```

**Step 2: Commit**

```bash
git add plugins/agile-team/context/coordinator-context.md
git commit -m "docs: update coordinator-context for structured log interface"
```

---

### Task 6: Update `agile-cli` for JSONL format

**Files:**
- Modify: `tools/agile-cli/src/agile.ts`

**Step 1: Add LogEntry type**

After the `GoalsFile` interface, add:

```typescript
interface LogEntry {
  ts: string;
  goal: number | null;
  title: string;
  description?: string;
}
```

**Step 2: Update `parseStartTime` to read JSONL**

Replace the `parseStartTime` function:

```typescript
function parseStartTime(logPath: string): Date | null {
  try {
    const fd = fs.openSync(logPath, "r");
    const buf = Buffer.alloc(512);
    fs.readSync(fd, buf, 0, 512, 0);
    fs.closeSync(fd);
    const firstLine = buf.toString("utf-8").split("\n")[0];
    try {
      const entry: LogEntry = JSON.parse(firstLine);
      if (entry.ts) return new Date(entry.ts);
    } catch {
      // Legacy plain text format fallback
      const match = firstLine.match(/Session started (\S+)/);
      if (match) return new Date(match[1]);
    }
  } catch {
    // fall through
  }
  return null;
}
```

**Step 3: Add `parseLogEntries` helper**

After `parseStartTime`, add:

```typescript
function parseLogEntries(logPath: string): LogEntry[] {
  if (!fs.existsSync(logPath)) return [];
  const lines = fs.readFileSync(logPath, "utf-8").split("\n").filter((l) => l.trim());
  const entries: LogEntry[] = [];
  for (const line of lines) {
    try {
      entries.push(JSON.parse(line));
    } catch {
      // skip non-JSON lines (legacy format)
    }
  }
  return entries;
}
```

**Step 4: Update `cmdLog` to display structured entries**

Replace the `cmdLog` function:

```typescript
function cmdLog(session: SessionInfo, lines?: number, goalFilter?: number): void {
  const entries = parseLogEntries(session.logPath);

  if (entries.length === 0) {
    console.log("(log is empty)");
    return;
  }

  let filtered = entries;
  if (goalFilter !== undefined) {
    filtered = entries.filter((e) => e.goal === goalFilter);
  }

  const display = lines && lines > 0 ? filtered.slice(-lines) : filtered;

  for (const e of display) {
    const ts = formatDate(new Date(e.ts));
    const goalTag = e.goal !== null ? ` [G${e.goal}]` : "";
    const desc = e.description ? `\n    ${e.description}` : "";
    console.log(`[${ts}]${goalTag} ${e.title}${desc}`);
  }
}
```

**Step 5: Add `--goal` argument parsing to log command**

In the `main()` function, update the `log` command section:

```typescript
if (command === "log") {
  if (!args[1]) fatal('Session required. Run "agile sessions" to see list.');
  const session = resolveSession(sessions, args[1]);
  const linesIdx = args.indexOf("--lines");
  const lines = linesIdx >= 0 ? parseInt(args[linesIdx + 1], 10) : undefined;
  const goalIdx = args.indexOf("--goal");
  const goalFilter = goalIdx >= 0 ? parseInt(args[goalIdx + 1], 10) : undefined;
  cmdLog(session, lines, goalFilter);
  return;
}
```

**Step 6: Update `goalStatusSummary` to use JSONL-aware reading (no change needed — it reads goals JSON, not log)**

No change needed. `goalStatusSummary` reads `.goals.json`, not the log file.

**Step 7: Update usage text**

In `printUsage()`, add `--goal N` to the log line:

```
  agile-team log <session> [--lines N] [--goal N]  View session log
```

**Step 8: Update README**

Add `--goal N` to the log command in README:

```
agile-team log <session> [--lines N] [--goal N]  # View session log
```

**Step 9: Build and test**

```bash
cd tools/agile-cli && npm run build
```

Expected: Clean compilation, no errors.

Test with an existing session (will show no entries if all are old format — that's expected with hard break).

**Step 10: Commit**

```bash
git add tools/agile-cli/src/agile.ts tools/agile-cli/README.md
git commit -m "feat: agile-cli parses JSONL log format with --goal filter"
```

---

### Task 7: End-to-end verification

**Step 1: Create a test session JSONL file**

```bash
SESSIONS_DIR=$(find ~/.claude/plugins/cache -path "*/agile-team/*/.sessions" -type d 2>/dev/null | head -1)
TEST_LOG="$SESSIONS_DIR/test-structured.log"
TEST_GOALS="$SESSIONS_DIR/test-structured.goals.json"

# Create goals file
cat > "$TEST_GOALS" << 'EOF'
{
  "goals": [
    { "id": 1, "description": "First goal", "status": "completed" },
    { "id": 2, "description": "Second goal", "status": "active" }
  ]
}
EOF

# Create JSONL log with entries across goals
cat > "$TEST_LOG" << 'EOF'
{"ts":"2026-03-01T10:00:00.000Z","goal":null,"title":"Session started"}
{"ts":"2026-03-01T10:01:00.000Z","goal":1,"title":"Goal 1 started"}
{"ts":"2026-03-01T10:02:00.000Z","goal":1,"title":"Task assigned to Engineer","description":"Build the login form with email validation"}
{"ts":"2026-03-01T10:03:00.000Z","goal":1,"title":"Goal 1 complete"}
{"ts":"2026-03-01T10:04:00.000Z","goal":2,"title":"Goal 2 started"}
{"ts":"2026-03-01T10:05:00.000Z","goal":2,"title":"PA delivered research","description":"Found 3 competing approaches. Recommending option A."}
{"ts":"2026-03-01T10:06:00.000Z","goal":2,"title":"Architect designing"}
{"ts":"2026-03-01T10:07:00.000Z","goal":2,"title":"Architect delivered breakdown","description":"4 tasks, 2 independent, 2 sequential."}
{"ts":"2026-03-01T10:08:00.000Z","goal":2,"title":"Task #5 done, commit abc1234","description":"Login form with validation. All checks pass."}
{"ts":"2026-03-01T10:09:00.000Z","goal":2,"title":"Architect APPROVED Task #5"}
EOF
```

**Step 2: Verify CLI reads it**

```bash
agile-team sessions          # Should show test-structured session
agile-team log <id>          # Should show all 10 entries formatted
agile-team log <id> --goal 2 # Should show only goal 2 entries (6)
agile-team log <id> --lines 3 # Should show last 3 entries
```

**Step 3: Clean up test files**

```bash
rm "$TEST_LOG" "$TEST_GOALS"
```
