# Auto-Loading Role Prompts

**Date:** 2026-03-06
**Status:** Approved

## Problem

The coordinator is responsible for including exact role prompts when spawning agents. In long sessions, it does this unreliably — agents get spawned with incomplete or missing role context, degrading team quality.

## Research Findings

Research across AutoGen, Anthropic, Google ADK, CrewAI, MetaGPT, and academic papers converges on one point: coordinators should NOT carry full worker role prompts. Key evidence:

- **AutoGen (Microsoft):** Switching from full system prompts to short descriptions doubled problems solved on first turn, halved distractor invocations.
- **Chroma Research ("Context Rot"):** LLM performance degrades with every additional token. Redundant role descriptions are deadweight.
- **Cemri et al. (2025):** When coordinators have detailed worker knowledge, they simulate worker behavior instead of delegating (role bleed, FM-1.2).
- **Anthropic guidance:** Orchestrators should provide objectives and output formats, not embed worker system prompts.

Full references in the research section below.

## Solution

Move role prompts out of the coordinator's context and into auto-loaded files. The coordinator gets short "role interfaces" (~50 tokens each) for orchestration. Full role prompts are injected into agents automatically by the existing `inject-role-context.sh` hook.

## Design

### New Files

```
plugins/agile-team/
  context/
    roles/
      product-analyst.md    # Full role prompt
      psychologist.md
      architect.md
      engineer.md
      designer.md
      qa.md
```

### Session Start: `.agile-team/` Population

On `/agile-team` invocation, `activate-mode.sh` populates the project's `.agile-team/` directory:

- Iterates over `context/roles/*.md`, copies each to `.agile-team/` if missing
- Creates empty `project.md` if missing (placeholder for user customization)
- Never overwrites existing files

```bash
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

### Name Matching: Longest Prefix Against Existing Files

When an agent is spawned (e.g., `qa-auth-specialist-3`), the hook scans `.agile-team/*.md` and finds the file whose stem is the longest prefix of the agent name.

```
product-analyst-2       → product-analyst.md  (starts with "product-analyst")
engineer-backend-2      → engineer.md         (starts with "engineer")
qa-auth-specialist-3    → qa.md               (starts with "qa")
designer-3              → designer.md         (starts with "designer")
```

If a user adds `qa-auth.md`, then `qa-auth-specialist-3` matches both `qa` (len 2) and `qa-auth` (len 7) — longest match wins → `qa-auth.md`.

Implementation:

```bash
BEST_MATCH=""
BEST_LEN=0
for role_file in .agile-team/*.md; do
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
```

### Project Context: Skip Empty

`project.md` is only injected if non-empty (`[ -s ".agile-team/project.md" ]`). This lets the empty file serve as a discoverable placeholder without polluting agent prompts.

### Coordinator Context: Role Interfaces

Replace the full role prompts in `coordinator-context.md` with short interfaces:

```markdown
### Team Roles

Role prompts are auto-injected into agents via .agile-team/*.md files.
You do NOT need to include role prompts when spawning agents — just provide the task.

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

## Files Changed

| File | Change |
|---|---|
| `context/roles/*.md` (6 new) | Full role prompts extracted from coordinator-context.md |
| `hooks/activate-mode.sh` | Populate `.agile-team/` with defaults on session start |
| `hooks/inject-role-context.sh` | Longest-prefix name matching; skip empty project.md |
| `context/coordinator-context.md` | Replace full role prompts with ~50-token interfaces |

## Research References

- [AutoGen: All About Agent Descriptions](https://microsoft.github.io/autogen/0.2/blog/2023/12/29/AgentDescriptions/)
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Anthropic: Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Google ADK: Multi-Agent Systems](https://google.github.io/adk-docs/agents/multi-agents/)
- [Chroma Research: Context Rot](https://research.trychroma.com/context-rot)
- [Cemri et al.: Why Do Multi-Agent LLM Systems Fail?](https://arxiv.org/html/2503.13657v1)
- [Embodied LLM Agents Learn to Cooperate in Organized Teams](https://arxiv.org/html/2403.12482v2)
- [Kurtis Kemple: Measuring Context Pollution](https://kurtiskemple.com/blog/measuring-context-pollution/)
- [JetBrains Research: Efficient Context Management](https://blog.jetbrains.com/research/2025/12/efficient-context-management/)
