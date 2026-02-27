#!/bin/bash
# Detects /agile-team command invocation and creates a per-session marker.
# Runs on every UserPromptSubmit — exits fast when not relevant.

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Match both raw command invocation and expanded markdown
if echo "$PROMPT" | grep -qE "AGILE_TEAM_ACTIVATED|^/agile-team|agile-team:agile-team"; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
  if [ -n "$SESSION_ID" ]; then
    MARKER_DIR="${CLAUDE_PLUGIN_ROOT}/.sessions"
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_DIR/$SESSION_ID"
  fi
fi

exit 0
