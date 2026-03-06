#!/bin/bash
# PreToolUse hook: auto-injects project + role-specific context into Task spawn prompts.
# Checks .agile-team/project.md (shared) and .agile-team/{match}.md (role-specific).
# Uses longest-prefix matching: agent name "qa-auth-specialist" matches "qa.md".
# Only active in agile-team sessions. Skips agent resumes.

CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

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
[ -n "$AGENT_NAME" ] || exit 0
CURRENT_PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // empty')

EXTRA=""

# Shared project context (skip if empty)
if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
  EXTRA="${EXTRA}

## Project Context

$(cat .agile-team/project.md)"
fi

# Role-specific context: find the .agile-team/*.md file whose stem is the
# longest prefix of the agent name, delimited by hyphen or exact match.
# E.g. "product-analyst-2" matches "product-analyst.md", "qa-auth" matches "qa.md".
# Uses case/glob (no regex) to avoid injection via filenames.
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
  EXTRA="${EXTRA}

<!-- agile-role:${ROLE_STEM} -->

$(cat "$BEST_MATCH")

Every input passes through your perspective first — it shapes what you notice, what you question, and what you say.

If your context was compacted, re-read your role from .agile-team/${ROLE_STEM}.md"
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
