#!/bin/bash
# Re-injects agile context after compaction.
# Uses the <!-- agile-role:X --> transcript marker to identify the role.
# Coordinator gets full coordinator context + log.
# Teammates get their role-specific context.

CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

# Detect role from transcript marker (works for both coordinator and teammates)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
ROLE_NAME=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  ROLE_NAME=$(grep -o 'agile-role:[a-z-]*' "$TRANSCRIPT" | head -1 | cut -d: -f2)
fi
[ -z "$ROLE_NAME" ] && exit 0

# Coordinator session
if [ "$ROLE_NAME" = "coordinator" ]; then
  cat "${CLAUDE_PLUGIN_ROOT}/context/coordinator-context.md"

  if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
    echo ""
    echo "## Project Context"
    echo ""
    cat ".agile-team/project.md"
  fi

  SESSION_LOG="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.log"
  GOALS_FILE="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.goals.json"

  if [ -f "$GOALS_FILE" ]; then
    GOAL_ID=$(jq -r '.goals[] | select(.status == "active") | .id' "$GOALS_FILE" 2>/dev/null)
    if [ -n "$GOAL_ID" ]; then
      DESC=$(jq -r '.goals[] | select(.status == "active") | .description' "$GOALS_FILE")
      echo ""
      echo "## Active Goal"
      echo "Goal ${GOAL_ID}: ${DESC}"
    else
      echo ""
      echo "## Goals"
      echo "All goals complete."
    fi
  fi

  echo ""
  echo "## Coordinator Log (last 10 entries — use coordinator_log_read for full history)"
  echo ""

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
fi

# Teammate session — re-inject role context
if [ -f ".agile-team/${ROLE_NAME}.md" ]; then
  echo "## Your Role Context"
  echo "<!-- agile-role:${ROLE_NAME} -->"
  echo ""
  cat ".agile-team/${ROLE_NAME}.md"
  echo ""
  echo "If your context was compacted, re-read your role from .agile-team/${ROLE_NAME}.md"
fi
if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
  echo ""
  echo "## Project Context"
  echo ""
  cat ".agile-team/project.md"
fi

exit 0
