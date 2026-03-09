#!/bin/bash
# PreToolUse hook: gates coordinator-log MCP tool calls.
#
# Four gates, all must pass:
#   1. session_id exists
#   2. session log file exists (active agile session)
#   3. coordinator marker FILE exists (created by activate-mode)
#   4. transcript_path does NOT contain /subagents/ (caller is coordinator, not agent)
#
# Gate 3 uses a file marker because UserPromptSubmit hook output and @file
# references do NOT persist to the JSONL transcript.
#
# Gate 4: subagents get transcript paths under subagents/agent-{id}.jsonl.
# The coordinator's transcript is the top-level session JSONL.

CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

DEBUG_LOG="/tmp/agile-session.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [inject-session] $*" >> "$DEBUG_LOG"; }

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
log "tool=$TOOL_NAME session=$SESSION_ID transcript=$TRANSCRIPT"

# --- Gate 1: session_id ---
if [ -z "$SESSION_ID" ]; then
  log "BLOCK no session_id"
  exit 0
fi

# --- Gate 2: active agile session ---
SESSIONS_DIR="${CLAUDE_PLUGIN_ROOT}/.sessions"
SESSION_LOG="${SESSIONS_DIR}/${SESSION_ID}.log"
if [ ! -f "$SESSION_LOG" ]; then
  log "BLOCK no session log"
  exit 0
fi

# --- Gate 3: coordinator marker file ---
COORDINATOR_MARKER="${SESSIONS_DIR}/${SESSION_ID}.coordinator"
if [ ! -f "$COORDINATOR_MARKER" ]; then
  log "BLOCK no coordinator marker file"
  exit 0
fi

# --- Gate 4: transcript_path must NOT be a subagent path ---
if [ -n "$TRANSCRIPT" ] && echo "$TRANSCRIPT" | grep -q '/subagents/'; then
  log "BLOCK subagent transcript path"
  exit 0
fi

log "ALLOW coordinator confirmed"

# --- All gates passed: inject session_id ---
UPDATED=$(echo "$TOOL_INPUT" | jq --arg sid "$SESSION_ID" '. + {session_id: $sid}')

jq -n --argjson updated "$UPDATED" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: $updated
  }
}'
log "session_id injected"
exit 0
