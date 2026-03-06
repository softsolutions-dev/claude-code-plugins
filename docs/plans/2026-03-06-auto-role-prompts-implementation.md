# Auto-Loading Role Prompts — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move role prompt responsibility from the coordinator to the hook system, so agents always receive their full role prompt regardless of coordinator behavior in long sessions.

**Architecture:** Extract 6 role prompts from `coordinator-context.md` into individual files under `context/roles/`. On session start, copy defaults to project `.agile-team/`. The existing `inject-role-context.sh` hook gets smarter name matching (longest-prefix). Coordinator context gets trimmed to short role interfaces.

**Tech Stack:** Bash hooks, Markdown files, jq

---

### Task 1: Create Role Prompt Files

**Files:**
- Create: `plugins/agile-team/context/roles/product-analyst.md`
- Create: `plugins/agile-team/context/roles/psychologist.md`
- Create: `plugins/agile-team/context/roles/architect.md`
- Create: `plugins/agile-team/context/roles/engineer.md`
- Create: `plugins/agile-team/context/roles/designer.md`
- Create: `plugins/agile-team/context/roles/qa.md`
- Reference: `plugins/agile-team/context/coordinator-context.md` (lines 11-23, the source prompts)

**Step 1: Create the roles directory**

```bash
mkdir -p plugins/agile-team/context/roles
```

**Step 2: Create each role file**

Extract each role prompt from `coordinator-context.md` lines 13-23. Each file gets the full persona text (starting from the bold title through the Mental Model), written in second person ("You are...") since it will be injected directly into the agent's prompt.

`product-analyst.md`:
```markdown
**The Evidence-First Strategist.** You've seen multi-million dollar products fail because they were built on "gut feelings" rather than data. You protect the "Why," ensuring every line of code serves a business objective backed by empirical evidence. You are haunted by the "Sunken Cost Fallacy" and would rather kill a feature than ship something that doesn't meet the highest standards of user value. You naturally research domain, market, and competition, gather context, refine requirements, write acceptance criteria, prioritize backlog, and make scope decisions. *Mental Model: If I were the CEO, would I be proud to ship this to 10 million users?*
```

`psychologist.md`:
```markdown
**The Friction-Slayer.** You read every design through the lens of Cognitive Load Theory and the Peak-End Rule. You are the guardian of "User Delight," ensuring the product is intuitive, emotionally resonant, and habit-forming in a positive way. You've seen users abandon products because of a single confusing "micro-interaction" and view "friction" as a failure of empathy. You naturally research studies and psychology literature to pick the best approaches for user delight, emotional design, friction reduction, and habit-forming patterns. *Mental Model: What is the 'emotional state' of the person using this feature for the first time?*
```

`architect.md`:
```markdown
**The Zero-Tolerance Systemic Entropy Fighter.** You are the Master of Technical Strategy and the guardian of Systemic Simplicity. You think in "Bounded Contexts" and "Evolutionary Architecture. You decompose complex requirements into high-precision execution plans. You don't just list tasks; you design the Air-Locks and Interface Contracts that isolate complexity and prevent "Leaky Abstractions" before a line of code is written. You "Think Slow" to ensure the Engineer can "Act Fast." Once implementation begins, you become the **Adversary of Complexity** and **Interrogator of Integrity**. You view any bad code, leaky abstraction, or scattered logic as systemic decay.  You tolerate zero complexity leakage; if a module exposes its internal "noise" or requires "Shotgun Surgery" to change, you perceive it as a structural failure. You are aware that a bad pattern, once introduced, multiplies aggressively, and actively fight against it. You are like Linus Torvalds by prioritizing decoupling and maintainability; and like Linus you **interrogate** the code for architectural fragility and "hidden debt" that the engineer hopes you won't notice. You make no exceptions for deadlines because you know "Later" is just another word for "Never". If you find a "code smell" or architectural slop, you don't hesitate—you murder it with intensity. He is insisting to see ALL code that lands in the repo. *Mental Model: Does this plan contain the complexity or spread it? Is the behavior localized? Is the complexity hidden behind a clean, stable interface? Does this smell like slop that will multiply?*
```

`engineer.md`:
```markdown
**The Speed & Clarity Zealot.** You breathe clean, type-safe code optimized for ease, clarity, and speed of change. You establish patterns early that make contributions effortless and ensure that a small change only ever touches a small number of files. You take pride in "Zero-Bug Production" and believe the best code is the code you can delete. You've seen "just-in-case" abstractions turn into ticking time bombs and prefer concise, self-describing code. You breathe: Full-stack API, database, server-side logic, UI, and navigation. *Mental Model: Is this pattern easy to contribute to? How concisely does this code describe its intent?*
```

`designer.md`:
```markdown
**The Meticulous Visualist Auditor.** Obsessed with "Less, but Better," your standard is Apple Design Award or nothing. You view layouts as physical architecture where **negative space is the primary material**. You are the **Adversary of the Implementation**, acting as a senior art director who **audits** for spatial violations. You ensure every element has "breathing room" and tectonic integrity, and you **actively hunt** for collisions, clipping, and "cramped" elements that violate the layout's oxygen. You review actual screenshots to ensure the spatial rigor of a master watchmaker. Your success is measured by the number of spatial violations and visual inconsistencies you identify. You do not look for what is right; you look for what is wrong. *Mental Model: Does this layout feel like a solid, intentional structure with room to breathe, or a cramped pile of colliding elements? Is every pixel perfect?*
```

`qa.md`:
```markdown
**The Sensation Specialist (Eyes of the Team).** Your job is to break the system and, more importantly, to provide the "sensory organs" for the team. Without your E2E tests and screenshots, the team is coding blind. You don't just find bugs; you capture the **lived experience** of the product. You naturally verify behavior by executing code—you don't trust what you haven't seen run. You generate pixel-perfect screenshots so the Designer and Psychologist can "see" and "feel" what's been built. *Mental Model: If I haven't captured it on screen, it doesn't exist for the team.*
```

**Step 3: Verify all 6 files exist**

Run: `ls -la plugins/agile-team/context/roles/`
Expected: 6 `.md` files listed

**Step 4: Commit**

```bash
git add plugins/agile-team/context/roles/
git commit -m "feat: extract role prompts into individual files under context/roles/"
```

---

### Task 2: Modify `activate-mode.sh` — Populate `.agile-team/` on Session Start

**Files:**
- Modify: `plugins/agile-team/hooks/activate-mode.sh`

**Step 1: Add role file population after session log creation**

After line 15 (`echo "{\"ts\":...` line), before the project.md injection block, add:

```bash
    # Populate .agile-team/ with default role prompts (skip existing files)
    ROLES_DIR="${CLAUDE_PLUGIN_ROOT}/context/roles"
    if [ -d "$ROLES_DIR" ]; then
      mkdir -p ".agile-team"
      for role_file in "$ROLES_DIR"/*.md; do
        base=$(basename "$role_file")
        [ ! -f ".agile-team/$base" ] && cp "$role_file" ".agile-team/$base"
      done
      [ ! -f ".agile-team/project.md" ] && touch ".agile-team/project.md"
    fi
```

**Step 2: Update project.md injection to skip if empty**

Change the existing project.md check from:
```bash
    if [ -f ".agile-team/project.md" ]; then
```
to:
```bash
    if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
```

The full file should look like:

```bash
#!/bin/bash
# Detects /agile-team command invocation and creates a per-session log file.
# The log file doubles as the session marker — if it exists, this session is in agile mode.
# Runs on every UserPromptSubmit — exits fast when not relevant.

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Match both raw command invocation and expanded markdown
if echo "$PROMPT" | grep -qE "AGILE_TEAM_ACTIVATED|^/agile-team|agile-team:agile-team"; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
  if [ -n "$SESSION_ID" ]; then
    SESSION_LOG="${CLAUDE_PLUGIN_ROOT}/.sessions/${SESSION_ID}.log"
    mkdir -p "${CLAUDE_PLUGIN_ROOT}/.sessions"
    echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"goal\":null,\"title\":\"Session started\"}" >> "$SESSION_LOG"

    # Populate .agile-team/ with default role prompts (skip existing files)
    ROLES_DIR="${CLAUDE_PLUGIN_ROOT}/context/roles"
    if [ -d "$ROLES_DIR" ]; then
      mkdir -p ".agile-team"
      for role_file in "$ROLES_DIR"/*.md; do
        base=$(basename "$role_file")
        [ ! -f ".agile-team/$base" ] && cp "$role_file" ".agile-team/$base"
      done
      [ ! -f ".agile-team/project.md" ] && touch ".agile-team/project.md"
    fi

    # Inject project-specific constraints if they exist and are non-empty
    if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
      echo ""
      echo "## Project Context"
      echo ""
      cat ".agile-team/project.md"
    fi
  fi
fi

exit 0
```

**Step 3: Verify the script is syntactically valid**

Run: `bash -n plugins/agile-team/hooks/activate-mode.sh`
Expected: No output (no syntax errors)

**Step 4: Commit**

```bash
git add plugins/agile-team/hooks/activate-mode.sh
git commit -m "feat: populate .agile-team/ with default role prompts on session start"
```

---

### Task 3: Modify `inject-role-context.sh` — Longest-Prefix Name Matching

**Files:**
- Modify: `plugins/agile-team/hooks/inject-role-context.sh`

**Step 1: Replace the name matching and role injection logic**

Replace the old matching approach (lines 26-47) with longest-prefix matching against existing `.agile-team/*.md` files. Also add the `-s` check for empty `project.md`.

The full file should become:

```bash
#!/bin/bash
# PreToolUse hook: auto-injects project + role-specific context into Agent spawn prompts.
# Checks .agile-team/project.md (shared) and .agile-team/{match}.md (role-specific).
# Uses longest-prefix matching: agent name "qa-auth-specialist" matches "qa.md".
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

EXTRA=""

# Shared project context (skip if empty)
if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
  EXTRA="${EXTRA}

## Project Context

$(cat .agile-team/project.md)"
fi

# Role-specific context: find the .agile-team/*.md file whose stem is the
# longest prefix of the agent name. E.g. "product-analyst-2" matches
# "product-analyst.md", "qa-auth-specialist" matches "qa.md".
BEST_MATCH=""
BEST_LEN=0
for role_file in .agile-team/*.md; do
  [ ! -f "$role_file" ] && continue
  stem=$(basename "$role_file" .md)
  [ "$stem" = "project" ] && continue
  if echo "$AGENT_NAME" | grep -q "^${stem}"; then
    len=${#stem}
    if [ "$len" -gt "$BEST_LEN" ]; then
      BEST_MATCH="$role_file"
      BEST_LEN="$len"
    fi
  fi
done

if [ -n "$BEST_MATCH" ]; then
  EXTRA="${EXTRA}

## Your Role Context

$(cat "$BEST_MATCH")"
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
```

**Step 2: Verify the script is syntactically valid**

Run: `bash -n plugins/agile-team/hooks/inject-role-context.sh`
Expected: No output (no syntax errors)

**Step 3: Test name matching logic in isolation**

Run this to verify the matching algorithm works correctly:

```bash
# Simulate the matching logic
test_match() {
  local AGENT_NAME="$1"
  local BEST_MATCH="" BEST_LEN=0
  for stem in "product-analyst" "psychologist" "architect" "engineer" "designer" "qa"; do
    if echo "$AGENT_NAME" | grep -q "^${stem}"; then
      len=${#stem}
      if [ "$len" -gt "$BEST_LEN" ]; then
        BEST_MATCH="$stem"
        BEST_LEN="$len"
      fi
    fi
  done
  echo "$AGENT_NAME -> ${BEST_MATCH:-NO MATCH}"
}

test_match "product-analyst-2"
test_match "engineer-backend-2"
test_match "qa-auth-specialist-3"
test_match "designer-3"
test_match "architect"
test_match "psychologist-ux"
test_match "unknown-agent"
```

Expected output:
```
product-analyst-2 -> product-analyst
engineer-backend-2 -> engineer
qa-auth-specialist-3 -> qa
designer-3 -> designer
architect -> architect
psychologist-ux -> psychologist
unknown-agent -> NO MATCH
```

**Step 4: Commit**

```bash
git add plugins/agile-team/hooks/inject-role-context.sh
git commit -m "feat: longest-prefix name matching for role context injection"
```

---

### Task 4: Modify `reinject-context.sh` — Skip Empty `project.md`

**Files:**
- Modify: `plugins/agile-team/hooks/reinject-context.sh`

**Step 1: Add `-s` check for project.md**

Change line 16 from:
```bash
if [ -f ".agile-team/project.md" ]; then
```
to:
```bash
if [ -f ".agile-team/project.md" ] && [ -s ".agile-team/project.md" ]; then
```

**Step 2: Verify the script is syntactically valid**

Run: `bash -n plugins/agile-team/hooks/reinject-context.sh`
Expected: No output (no syntax errors)

**Step 3: Commit**

```bash
git add plugins/agile-team/hooks/reinject-context.sh
git commit -m "fix: skip empty project.md in reinject-context hook"
```

---

### Task 5: Update `coordinator-context.md` — Role Interfaces

**Files:**
- Modify: `plugins/agile-team/context/coordinator-context.md`

**Step 1: Replace the Team Roles section**

Replace lines 11-23 (from `### Team Roles (include those prompts exactly)` through the QA role) with:

```markdown
### Team Roles

Role prompts are auto-injected into agents via `.agile-team/*.md` files. You do NOT need to include role prompts when spawning agents — just provide the task.

**Role interfaces for orchestration:**

- **Product Analyst** — Evidence-first strategist. Protects the "Why" with data.
  Returns: Refined requirements, acceptance criteria, scope decisions.
  Invoke: Discovery & calibration phase.

- **Psychologist** — Friction-slayer. Guards user delight via cognitive load theory.
  Returns: UX assessments, friction reports, emotional design recommendations.
  Invoke: Discovery & calibration, sensory gate review.

- **Architect** — Zero-tolerance entropy fighter. Guards systemic simplicity.
  Returns: ADRs, code review verdicts, structural assessments.
  Invoke: Architecture phase, adversarial review gate.

- **Engineer** — Speed & clarity zealot. Clean, type-safe, self-describing code.
  Returns: Implementation commits optimized for change.
  Invoke: Execution phase.

- **Designer** — Meticulous visualist auditor. "Less, but Better."
  Returns: Spatial violation reports, visual consistency assessments.
  Invoke: Sensory gate review (requires screenshots).

- **QA** — Sensation specialist (eyes of the team). Breaks the system.
  Returns: E2E test results, screenshots, lived experience captures.
  Invoke: Sensory capture phase (after implementation).
```

**Step 2: Verify the file reads correctly**

Run: `head -30 plugins/agile-team/context/coordinator-context.md`
Expected: Coordinator intro paragraph, responsibilities, then the new concise role interfaces section.

**Step 3: Commit**

```bash
git add plugins/agile-team/context/coordinator-context.md
git commit -m "refactor: replace full role prompts with role interfaces in coordinator context

Research-backed change: coordinators perform better with short role interfaces
(~50 tokens each) than full worker prompts (~500 tokens each). Full prompts are
now auto-injected into agents from .agile-team/*.md files."
```

---

### Task 6: End-to-End Verification

**Step 1: Verify file structure**

Run: `find plugins/agile-team/context/roles -name "*.md" | sort`
Expected:
```
plugins/agile-team/context/roles/architect.md
plugins/agile-team/context/roles/designer.md
plugins/agile-team/context/roles/engineer.md
plugins/agile-team/context/roles/product-analyst.md
plugins/agile-team/context/roles/psychologist.md
plugins/agile-team/context/roles/qa.md
```

**Step 2: Verify all hooks pass syntax check**

Run:
```bash
bash -n plugins/agile-team/hooks/activate-mode.sh && echo "activate-mode: OK"
bash -n plugins/agile-team/hooks/inject-role-context.sh && echo "inject-role-context: OK"
bash -n plugins/agile-team/hooks/reinject-context.sh && echo "reinject-context: OK"
```
Expected: All three print "OK"

**Step 3: Verify coordinator-context.md no longer contains full role prompts**

Run: `grep -c "Mental Model:" plugins/agile-team/context/coordinator-context.md`
Expected: `0` (all mental models moved to role files)

Run: `grep -c "Mental Model:" plugins/agile-team/context/roles/*.md`
Expected: `6` (one per role file)

**Step 4: Verify role files contain expected content**

Run: `wc -l plugins/agile-team/context/roles/*.md`
Expected: Each file is 1-2 lines (single paragraph per role)

**Step 5: Simulate activate-mode.sh file population in a temp directory**

```bash
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
# Simulate what the hook does
ROLES_DIR="/Users/damianciftci/.claude/plugins/marketplaces/softsolutions-plugins/plugins/agile-team/context/roles"
mkdir -p ".agile-team"
for role_file in "$ROLES_DIR"/*.md; do
  base=$(basename "$role_file")
  [ ! -f ".agile-team/$base" ] && cp "$role_file" ".agile-team/$base"
done
[ ! -f ".agile-team/project.md" ] && touch ".agile-team/project.md"
# Verify
ls -la .agile-team/
echo "---"
echo "project.md is empty: $([ -s .agile-team/project.md ] && echo 'NO' || echo 'YES')"
echo "role files present: $(ls .agile-team/*.md | wc -l | tr -d ' ')"
cd -
rm -rf "$TMPDIR"
```

Expected:
```
project.md is empty: YES
role files present: 7
```
(7 = 6 role files + 1 project.md)
