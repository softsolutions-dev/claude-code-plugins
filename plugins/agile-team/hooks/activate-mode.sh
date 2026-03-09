#!/bin/bash
# UserPromptSubmit hook: detects /agile-team activation.
# Creates session log + coordinator marker FILE.
#
# Key insight: UserPromptSubmit hook stdout and @file references do NOT
# persist to the JSONL transcript. So we use a file-based marker instead.

CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

DEBUG_LOG="/tmp/agile-session.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [activate-mode] $*" >> "$DEBUG_LOG"; }

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Only trigger on agile-team activation
if ! echo "$PROMPT" | grep -qE "AGILE_TEAM_ACTIVATED|^/agile-team|agile-team:agile-team"; then
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
log "activation session=$SESSION_ID transcript=$TRANSCRIPT"

if [ -z "$SESSION_ID" ]; then
  log "WARNING: no session_id"
  exit 0
fi

# Safety: skip if this is a subagent context
if [ -n "$TRANSCRIPT" ] && echo "$TRANSCRIPT" | grep -q '/subagents/'; then
  log "SKIP subagent transcript"
  exit 0
fi

SESSIONS_DIR="${CLAUDE_PLUGIN_ROOT}/.sessions"
SESSION_LOG="${SESSIONS_DIR}/${SESSION_ID}.log"
COORDINATOR_MARKER="${SESSIONS_DIR}/${SESSION_ID}.coordinator"
mkdir -p "$SESSIONS_DIR"

# Create session log (doubles as "in agile mode" marker)
if [ ! -f "$SESSION_LOG" ]; then
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"goal\":null,\"title\":\"Session started\"}" >> "$SESSION_LOG"
  log "session log created"
fi

# Create coordinator marker file — this is how inject-session detects the coordinator
echo "$SESSION_ID" > "$COORDINATOR_MARKER"
log "coordinator marker file created"

# Copy default role files (skip existing)
ROLES_DIR="${CLAUDE_PLUGIN_ROOT}/context/roles"
if [ -d "$ROLES_DIR" ]; then
  mkdir -p ".agile-team"
  for role_file in "$ROLES_DIR"/*.md; do
    [ -f "$role_file" ] || continue
    base=$(basename "$role_file")
    [ ! -f ".agile-team/$base" ] && cp "$role_file" ".agile-team/$base"
  done
  [ ! -f ".agile-team/project.md" ] && touch ".agile-team/project.md"
fi

# Project context output (goes into user prompt)
if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
  echo ""
  echo "## Project Context"
  echo ""
  cat ".agile-team/project.md"
  log "project context injected"
fi

log "activation complete"
exit 0
