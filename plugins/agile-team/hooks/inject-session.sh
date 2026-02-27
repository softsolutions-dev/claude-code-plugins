#!/bin/bash
# PreToolUse hook: transparently injects session_id into MCP coordinator-log tool calls.
# The model never sees session_id — it's added after the model generates the call.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input')

# Inject session_id into the tool's input
UPDATED=$(echo "$TOOL_INPUT" | jq --arg sid "$SESSION_ID" '. + {session_id: $sid}')

# hookEventName is required for updatedInput to take effect
jq -n --argjson updated "$UPDATED" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: $updated
  }
}'
exit 0
