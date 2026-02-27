#!/bin/bash
# Removes per-session marker on session end.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [ -n "$SESSION_ID" ]; then
  rm -f "${CLAUDE_PLUGIN_ROOT}/.sessions/$SESSION_ID"
fi

exit 0
