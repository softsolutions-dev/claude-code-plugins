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

echo ""
echo "## Coordinator Log (last 300 lines — read full file if you need older history)"
echo ""
tail -300 "$SESSION_LOG"

exit 0
