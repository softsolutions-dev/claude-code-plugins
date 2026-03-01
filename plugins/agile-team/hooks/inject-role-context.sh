#!/bin/bash
# PreToolUse hook: auto-injects project + role-specific context into Agent spawn prompts.
# Checks .agile-team/project.md (shared) and .agile-team/{name}.md (role-specific).
# Only active in agile-team sessions. Skips agent resumes.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SESSION_LOG="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.log"

# Only active in agile-team sessions
if [ -z "$SESSION_ID" ] || [ ! -f "$SESSION_LOG" ]; then
  exit 0
fi

TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input')

# Skip resumes — context was already injected at initial spawn
RESUME=$(echo "$TOOL_INPUT" | jq -r '.resume // empty')
if [ -n "$RESUME" ]; then
  exit 0
fi

AGENT_NAME=$(echo "$TOOL_INPUT" | jq -r '.name // empty')
CURRENT_PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // empty')

# Strip trailing -N suffix (e.g. designer-2 → designer, qa-3 → qa)
BASE_NAME=$(echo "$AGENT_NAME" | sed 's/-[0-9]*$//')

EXTRA=""

# Shared project context
if [ -f ".agile-team/project.md" ]; then
  EXTRA="${EXTRA}

## Project Context

$(cat .agile-team/project.md)"
fi

# Role-specific context (use base name to handle re-spawned agents like designer-2)
if [ -n "$BASE_NAME" ] && [ -f ".agile-team/${BASE_NAME}.md" ]; then
  EXTRA="${EXTRA}

## Your Role Context

$(cat ".agile-team/${BASE_NAME}.md")"
fi

# Nothing to inject
if [ -z "$EXTRA" ]; then
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
exit 0
