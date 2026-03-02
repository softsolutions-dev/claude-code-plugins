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

# Inject project-specific constraints if they exist
if [ -f ".agile-team/project.md" ]; then
  echo ""
  echo "## Project Context"
  echo ""
  cat ".agile-team/project.md"
fi

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
echo "## Coordinator Log (last 10 entries — use coordinator_log_read for full history)"
echo ""

# Parse JSONL, filter by active goal, format tiered (5 full + 10 title-only)
if [ -f "$SESSION_LOG" ]; then
  GOAL_FILTER="null"
  if [ -n "$GOAL_ID" ]; then
    GOAL_FILTER="$GOAL_ID"
  fi

  jq -rs --argjson goal "$GOAL_FILTER" '
    [ .[] | if $goal != null then select(.goal == $goal) else . end ] |
    .[-10:] |
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

exit 0
