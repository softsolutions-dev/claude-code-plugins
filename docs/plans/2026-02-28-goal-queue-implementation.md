# Goal Queue System — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add sequential goal management to the agile-team plugin so the team works one goal at a time with future goals invisible.

**Architecture:** Extend the existing `coordinator-log.js` MCP server with three new tools (`goal_add`, `goal_current`, `goal_complete`). Goals stored as JSON per-session. PreToolUse hook extended to inject `session_id` into goal tools. Context reinjection updated to include active goal after compaction. Coordinator context updated with goal workflow rules.

**Tech Stack:** Node.js (MCP server), Bash (hooks), JSON (storage), jq (hook processing)

---

### Task 1: Add goal tools to MCP server

**Files:**
- Modify: `plugins/agile-team/servers/coordinator-log.js`

**Step 1: Add goal tool definitions to TOOLS array**

After the existing `coordinator_log_read` tool definition (line 51), add three new tool definitions:

```javascript
  {
    name: 'goal_add',
    description: 'Add a goal to the queue. Goals are worked sequentially — one at a time.',
    inputSchema: {
      type: 'object',
      properties: {
        description: { type: 'string', description: 'Short description of the goal' }
      },
      required: ['description']
    }
  },
  {
    name: 'goal_current',
    description: 'Get the current active goal. Returns goal description and position (e.g., "Goal 2 of 4").',
    inputSchema: { type: 'object', properties: {} }
  },
  {
    name: 'goal_complete',
    description: 'Mark the current goal as complete and advance to the next one.',
    inputSchema: { type: 'object', properties: {} }
  }
```

**Step 2: Add goal helper functions**

After the `SESSIONS_DIR` constant (line 11), add helper functions for reading and writing goals:

```javascript
function goalsPath(sessionId) {
  return path.join(SESSIONS_DIR, `${sessionId}.goals.json`);
}

function readGoals(sessionId) {
  const p = goalsPath(sessionId);
  if (!fs.existsSync(p)) return { goals: [] };
  return JSON.parse(fs.readFileSync(p, 'utf-8'));
}

function writeGoals(sessionId, data) {
  fs.mkdirSync(SESSIONS_DIR, { recursive: true });
  fs.writeFileSync(goalsPath(sessionId), JSON.stringify(data, null, 2));
}
```

**Step 3: Add goal tool handlers**

In the `handleToolCall` function, after the `coordinator_log_read` handler block (line 85) and before the final `else` (line 87), add handlers for the three goal tools:

```javascript
  } else if (name === 'goal_add') {
    if (!args.description) {
      return respond(id, { content: [{ type: 'text', text: 'Error: description is required' }], isError: true });
    }
    try {
      const data = readGoals(sessionId);
      const goalId = data.goals.length + 1;
      const isFirst = data.goals.length === 0;
      data.goals.push({ id: goalId, description: args.description, status: isFirst ? 'active' : 'pending' });
      writeGoals(sessionId, data);
      respond(id, { content: [{ type: 'text', text: `Added goal ${goalId}: ${args.description}` }] });
    } catch (e) {
      respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
    }

  } else if (name === 'goal_current') {
    try {
      const data = readGoals(sessionId);
      const total = data.goals.length;
      if (total === 0) {
        return respond(id, { content: [{ type: 'text', text: 'No goals yet. Use goal_add to create goals.' }] });
      }
      const active = data.goals.find(g => g.status === 'active');
      if (!active) {
        return respond(id, { content: [{ type: 'text', text: 'All goals complete.' }] });
      }
      respond(id, { content: [{ type: 'text', text: `Goal ${active.id} of ${total}: ${active.description}` }] });
    } catch (e) {
      respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
    }

  } else if (name === 'goal_complete') {
    try {
      const data = readGoals(sessionId);
      const active = data.goals.find(g => g.status === 'active');
      if (!active) {
        return respond(id, { content: [{ type: 'text', text: 'No active goal to complete.' }] });
      }
      active.status = 'completed';
      const next = data.goals.find(g => g.status === 'pending');
      const total = data.goals.length;
      if (next) {
        next.status = 'active';
        writeGoals(sessionId, data);
        respond(id, { content: [{ type: 'text', text: `Goal ${active.id} complete. Now active — Goal ${next.id} of ${total}: ${next.description}` }] });
      } else {
        writeGoals(sessionId, data);
        respond(id, { content: [{ type: 'text', text: `All ${total} goals complete.` }] });
      }
    } catch (e) {
      respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
    }
```

**Step 4: Verify syntax**

Run: `node -c plugins/agile-team/servers/coordinator-log.js`
Expected: `Syntax OK` (no output, exit 0)

**Step 5: Commit**

```bash
git add plugins/agile-team/servers/coordinator-log.js
git commit -m "Add goal_add, goal_current, goal_complete tools to MCP server"
```

---

### Task 2: Extend PreToolUse hook matcher

**Files:**
- Modify: `plugins/agile-team/hooks/hooks.json`

**Step 1: Update the PreToolUse matcher**

Change the matcher from:
```json
"matcher": ".*coordinator_log.*"
```
To:
```json
"matcher": ".*coordinator_log.*|.*goal_.*"
```

This ensures `session_id` is injected into `goal_add`, `goal_current`, and `goal_complete` calls just like the coordinator log tools.

**Step 2: Verify JSON syntax**

Run: `python3 -c "import json; json.load(open('plugins/agile-team/hooks/hooks.json'))"`
Expected: No output (valid JSON)

**Step 3: Commit**

```bash
git add plugins/agile-team/hooks/hooks.json
git commit -m "Extend PreToolUse hook to inject session_id into goal tools"
```

---

### Task 3: Update context reinjection to include active goal

**Files:**
- Modify: `plugins/agile-team/hooks/reinject-context.sh`

**Step 1: Add active goal injection**

After the coordinator context is output (line 13: `cat "${CLAUDE_PLUGIN_ROOT}/context/coordinator-context.md"`) and before the coordinator log section (line 15), add goal injection:

```bash
# Inject active goal if goals exist
GOALS_FILE="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.goals.json"
if [ -f "$GOALS_FILE" ]; then
  ACTIVE=$(jq -r '.goals[] | select(.status == "active") | "\(.id) of \(.goals | length): \(.description)"' "$GOALS_FILE" 2>/dev/null || true)
  if [ -n "$ACTIVE" ]; then
    TOTAL=$(jq '.goals | length' "$GOALS_FILE")
    DESC=$(jq -r '.goals[] | select(.status == "active") | .description' "$GOALS_FILE")
    GOAL_ID=$(jq -r '.goals[] | select(.status == "active") | .id' "$GOALS_FILE")
    echo ""
    echo "## Active Goal"
    echo "Goal ${GOAL_ID} of ${TOTAL}: ${DESC}"
  else
    echo ""
    echo "## Goals"
    echo "All goals complete."
  fi
fi
```

**Step 2: Verify script syntax**

Run: `bash -n plugins/agile-team/hooks/reinject-context.sh`
Expected: No output (valid syntax)

**Step 3: Commit**

```bash
git add plugins/agile-team/hooks/reinject-context.sh
git commit -m "Inject active goal into context after compaction"
```

---

### Task 4: Update coordinator context with goal workflow

**Files:**
- Modify: `plugins/agile-team/context/coordinator-context.md`

**Step 1: Add Goal Management section**

After the "## Coordinator Log" section (end of file), add a new section:

```markdown
## Goals

Goals are the unit of delivery. Your first action after spawning the team: read the user's request and create goals via `goal_add` in priority order. Then call `goal_current` to begin.

Rules:
- Only break down the active goal. Future goals are invisible — do not plan, decompose, or discuss them.
- Call `goal_complete` only when all gates have passed for the current goal.
- When all goals are complete: summarize what was accomplished per goal and ask the user if there's more.

Use `goal_current` to check the active goal. Use `goal_add` to add new goals at any time (they queue behind the current one).
```

**Step 2: Update the command's first-action instruction**

In `plugins/agile-team/commands/agile-team.md`, update the instruction from:

```markdown
Your first action is to spawn ALL teammates below. The full team must exist before any work begins.
```

To:

```markdown
Your first action is to spawn ALL teammates below. The full team must exist before any work begins. Then create goals from the user's request via `goal_add` and call `goal_current` to start the first one.
```

**Step 3: Commit**

```bash
git add plugins/agile-team/context/coordinator-context.md plugins/agile-team/commands/agile-team.md
git commit -m "Add goal workflow rules to coordinator context"
```

---

### Task 5: Sync to cache and verify

**Step 1: Run sync script**

Run: `bash scripts/sync-cache.sh`
Expected: `Synced agile-team@1.0.0`

**Step 2: Verify synced files**

Run: `diff plugins/agile-team/servers/coordinator-log.js ~/.claude/plugins/cache/softsolutions-plugins/agile-team/1.0.0/servers/coordinator-log.js`
Expected: No output (identical)

Run: `diff plugins/agile-team/hooks/hooks.json ~/.claude/plugins/cache/softsolutions-plugins/agile-team/1.0.0/hooks/hooks.json`
Expected: No output (identical)

Run: `diff plugins/agile-team/hooks/reinject-context.sh ~/.claude/plugins/cache/softsolutions-plugins/agile-team/1.0.0/hooks/reinject-context.sh`
Expected: No output (identical)

Run: `diff plugins/agile-team/context/coordinator-context.md ~/.claude/plugins/cache/softsolutions-plugins/agile-team/1.0.0/context/coordinator-context.md`
Expected: No output (identical)

**Step 3: Commit sync (if sync script modifies any tracked files)**

No commit needed — sync only copies to cache dir which is outside the repo.

---

### Task 6: Push all changes

**Step 1: Push**

Run: `git push`
Expected: All commits pushed successfully.
