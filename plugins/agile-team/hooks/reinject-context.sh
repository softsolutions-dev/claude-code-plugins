#!/bin/bash
# Re-injects agile coordinator context + log after compaction.
# Only outputs when this session has agile-team mode active.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [ -z "$SESSION_ID" ] || [ ! -f "${CLAUDE_PLUGIN_ROOT}/.sessions/$SESSION_ID" ]; then
  exit 0
fi

cat "${CLAUDE_PLUGIN_ROOT}/context/coordinator-context.md"

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
LOG_FILE="$CWD/.claude/agile-coordinator.log"
if [ -f "$LOG_FILE" ]; then
  echo ""
  echo "## Coordinator Log (last 300 lines — read full file if you need older history)"
  echo ""
  tail -300 "$LOG_FILE"
fi

exit 0
