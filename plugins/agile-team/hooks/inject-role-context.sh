#!/bin/bash
# PreToolUse hook: injects role + project context into Task/Agent spawn prompts.
# Uses longest-prefix matching: agent name "qa-auth-specialist" matches "qa.md".
# Only active in agile sessions. Skips agent resumes.

CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

DEBUG_LOG="/tmp/agile-session.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [inject-role-context] $*" >> "$DEBUG_LOG"; }

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SESSION_LOG="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.log"

# Only active in agile sessions
if [ -z "$SESSION_ID" ] || [ ! -f "$SESSION_LOG" ]; then
  exit 0
fi

TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input')

# Skip resumes — context was already injected at initial spawn
RESUME=$(echo "$TOOL_INPUT" | jq -r '.resume // empty')
if [ -n "$RESUME" ]; then
  log "resume → skip"
  exit 0
fi

AGENT_NAME=$(echo "$TOOL_INPUT" | jq -r '.name // empty')
if [ -z "$AGENT_NAME" ]; then
  exit 0
fi

log "agent=$AGENT_NAME"

CURRENT_PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // empty')
EXTRA=""

# Role matching: find .agile-team/*.md whose stem is the longest prefix of agent name
BEST_MATCH=""
BEST_LEN=0
for role_file in .agile-team/*.md; do
  [ -f "$role_file" ] || continue
  stem=$(basename "$role_file" .md)
  [ "$stem" = "project" ] && continue
  case "$AGENT_NAME" in
    "$stem"|"${stem}-"*)
      len=${#stem}
      if [ "$len" -gt "$BEST_LEN" ]; then
        BEST_MATCH="$role_file"
        BEST_LEN="$len"
      fi
      ;;
  esac
done

if [ -n "$BEST_MATCH" ]; then
  ROLE_STEM=$(basename "$BEST_MATCH" .md)
  log "matched role=$ROLE_STEM from $BEST_MATCH"
  EXTRA="${EXTRA}

<!-- agile-role:${ROLE_STEM} -->

$(cat "$BEST_MATCH")

Every input passes through your perspective first — it shapes what you notice, what you question, and what you say.

If your context was compacted, re-read your role from .agile-team/${ROLE_STEM}.md"
else
  log "no role match for $AGENT_NAME"
fi

# Project context (skip if empty)
if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
  EXTRA="${EXTRA}

## Project Context

$(cat .agile-team/project.md)"
  log "project context injected"
fi

# Nothing to inject
if [ -z "$EXTRA" ]; then
  log "nothing to inject"
  exit 0
fi

UPDATED_PROMPT="${CURRENT_PROMPT}${EXTRA}"
UPDATED=$(echo "$TOOL_INPUT" | jq --arg prompt "$UPDATED_PROMPT" '.prompt = $prompt')

jq -n --argjson updated "$UPDATED" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: $updated
  }
}'
log "role+project context injected for $AGENT_NAME"
exit 0
