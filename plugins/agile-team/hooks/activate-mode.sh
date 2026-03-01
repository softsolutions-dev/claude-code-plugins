#!/bin/bash
# Detects /agile-team command invocation and creates a per-session log file.
# The log file doubles as the session marker — if it exists, this session is in agile mode.
# Runs on every UserPromptSubmit — exits fast when not relevant.

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Match both raw command invocation and expanded markdown
if echo "$PROMPT" | grep -qE "AGILE_TEAM_ACTIVATED|^/agile-team|agile-team:agile-team"; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
  if [ -n "$SESSION_ID" ]; then
    SESSION_LOG="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.log"
    mkdir -p "${CLAUDE_PLUGIN_ROOT}/.sessions"
    echo "--- Session started $(date -u +%Y-%m-%dT%H:%M:%SZ) ---" >> "$SESSION_LOG"

    # Inject project-specific constraints if they exist
    if [ -f ".agile-team.md" ]; then
      echo ""
      echo "## Project Context"
      echo ""
      cat ".agile-team.md"
    fi
  fi
fi

exit 0
