#!/bin/bash
# PreToolUse hook: transparently injects session_id into MCP coordinator-log tool calls.
# Blocks non-coordinator agents from using coordinator-only tools.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input')

# Check transcript for role marker — only coordinator can use these tools
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  ROLE_NAME=$(grep -o 'agile-role:[a-z-]*' "$TRANSCRIPT" | head -1 | cut -d: -f2)
  if [ -n "$ROLE_NAME" ] && [ "$ROLE_NAME" != "coordinator" ]; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        message: "Coordinator-only tool. Use SendMessage to report findings to the team lead."
      }
    }'
    exit 0
  fi
fi

# Inject session_id into the tool's input
UPDATED=$(echo "$TOOL_INPUT" | jq --arg sid "$SESSION_ID" '. + {session_id: $sid}')

jq -n --argjson updated "$UPDATED" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: $updated
  }
}'
exit 0
