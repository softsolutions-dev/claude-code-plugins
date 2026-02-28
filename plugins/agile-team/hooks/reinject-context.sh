#!/bin/bash
# Re-injects agile coordinator context + log after compaction.
# Only outputs when this session has agile-team mode active (log file exists).

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SESSION_LOG="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.log"

if [ -z "$SESSION_ID" ] || [ ! -f "$SESSION_LOG" ]; then
  exit 0
fi

cat "${CLAUDE_PLUGIN_ROOT}/context/coordinator-context.md"

# Inject active goal if goals exist
GOALS_FILE="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.goals.json"
if [ -f "$GOALS_FILE" ]; then
  GOAL_ID=$(jq -r '.goals[] | select(.status == "active") | .id' "$GOALS_FILE" 2>/dev/null)
  if [ -n "$GOAL_ID" ]; then
    TOTAL=$(jq '.goals | length' "$GOALS_FILE")
    DESC=$(jq -r '.goals[] | select(.status == "active") | .description' "$GOALS_FILE")
    echo ""
    echo "## Active Goal"
    echo "Goal ${GOAL_ID} of ${TOTAL}: ${DESC}"
  else
    echo ""
    echo "## Goals"
    echo "All goals complete."
  fi
fi

echo ""
echo "## Coordinator Log (last 30 lines — use coordinator_log_read for full history)"
echo ""
tail -30 "$SESSION_LOG"

exit 0
