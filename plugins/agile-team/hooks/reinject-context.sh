#!/bin/bash
# SessionStart:compact hook — re-injects context after compaction.
#
# Detection:
#   1. Coordinator marker file exists + transcript NOT under /subagents/
#      → coordinator context + log + goals
#   2. Transcript under /subagents/ with agent marker
#      → agent role context + project context
#   3. Otherwise → skip

CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

DEBUG_LOG="/tmp/agile-session.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [reinject-context] $*" >> "$DEBUG_LOG"; }

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

log "session=$SESSION_ID transcript=$TRANSCRIPT"

# Gate 1: session_id
if [ -z "$SESSION_ID" ]; then
  log "skip: no session_id"
  exit 0
fi

# Gate 2: active agile session
SESSIONS_DIR="${CLAUDE_PLUGIN_ROOT}/.sessions"
SESSION_LOG="${SESSIONS_DIR}/${SESSION_ID}.log"
if [ ! -f "$SESSION_LOG" ]; then
  log "skip: no session log"
  exit 0
fi

# Gate 3: detect role
COORDINATOR_MARKER="${SESSIONS_DIR}/${SESSION_ID}.coordinator"
IS_SUBAGENT=false
if [ -n "$TRANSCRIPT" ] && echo "$TRANSCRIPT" | grep -q '/subagents/'; then
  IS_SUBAGENT=true
fi

MARKER_EXISTS=false
[ -f "$COORDINATOR_MARKER" ] && MARKER_EXISTS=true

log "is_subagent=$IS_SUBAGENT coordinator_marker=$MARKER_EXISTS"

# --- Coordinator path ---
# Coordinator marker file exists AND not a subagent transcript
if [ "$MARKER_EXISTS" = true ] && [ "$IS_SUBAGENT" = false ]; then
  log "coordinator → injecting context"

  # Coordinator context (includes agile-role:coordinator for future detection)
  cat "${CLAUDE_PLUGIN_ROOT}/context/coordinator-context.md"

  # Project context
  if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
    echo ""
    echo "## Project Context"
    echo ""
    cat ".agile-team/project.md"
  fi

  # Active goal
  GOALS_FILE="${SESSIONS_DIR}/${SESSION_ID}.goals.json"
  GOAL_ID=""
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

  # Recent log entries
  echo ""
  echo "## Coordinator Log (last 10 entries — use coordinator_log_read for full history)"
  echo ""
  if [ -f "$SESSION_LOG" ]; then
    GOAL_FILTER="null"
    [ -n "$GOAL_ID" ] && GOAL_FILTER="$GOAL_ID"

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

  log "coordinator context injected"
  exit 0
fi

# --- Agent path ---
# Subagent transcript with agent role marker
if [ "$IS_SUBAGENT" = true ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  AGENT_ROLE=$(grep -o 'agile-role:[a-z-]*' "$TRANSCRIPT" 2>/dev/null | head -1 | cut -d: -f2)
  if [ -n "$AGENT_ROLE" ]; then
    log "agent role=$AGENT_ROLE → injecting context"

    echo "## Your Role Context"
    echo "<!-- agile-role:${AGENT_ROLE} -->"
    echo ""

    if [ -f ".agile-team/${AGENT_ROLE}.md" ]; then
      cat ".agile-team/${AGENT_ROLE}.md"
      echo ""
      echo "If your context was compacted, re-read your role from .agile-team/${AGENT_ROLE}.md"
    else
      log "WARNING: no role file at .agile-team/${AGENT_ROLE}.md"
    fi

    if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
      echo ""
      echo "## Project Context"
      echo ""
      cat ".agile-team/project.md"
    fi

    log "agent context injected"
    exit 0
  fi
fi

# --- No match ---
log "skip: no role detected"
exit 0
