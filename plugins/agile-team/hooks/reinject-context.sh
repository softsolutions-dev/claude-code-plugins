#!/bin/bash
# Re-injects agile coordinator context after compaction.
# Only outputs when this session has agile-team mode active.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [ -z "$SESSION_ID" ] || [ ! -f "${CLAUDE_PLUGIN_ROOT}/.sessions/$SESSION_ID" ]; then
  exit 0
fi

cat "${CLAUDE_PLUGIN_ROOT}/context/coordinator-context.md"
exit 0
