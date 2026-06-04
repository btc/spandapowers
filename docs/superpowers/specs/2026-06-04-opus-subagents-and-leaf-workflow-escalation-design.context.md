# Context: Opus Subagents + Leaf Workflow Escalation

Predecessor context for the burndown-reviews spec-stage pass.

## Original request

The user (btc, owner of this personal superpowers fork) asked for two things:

1. "Update spandapowers so that subagents use opus. no more sonnet in the tool."
2. "I'd like to see points where we can allow and adopt the usage of CC's native
   dynamic workflows." — find the integration touch points and adopt them.

A `TODO` file in the repo root already read: "figure out how this composes with
Claude's native dynamic workflows."

## Locked-in design decisions (from the brainstorming dialogue)

- **Deliverable:** implement *both* halves fully (not analysis-only).
- **Reviewer-pair carve-out:** "no more sonnet" does NOT apply to the burndown
  reviewer pair. The user explicitly said to keep Sonnet there: "for this
  reviewer comparison keep sonnet. that has value in that it's a different
  model." Cross-*model* diversity is the reason that pair exists.
- **Opus-only slots chosen by the user:** the SDD `Model Selection` section
  (force all SDD subagents to Opus) and the burndown fixer model (remove the
  "use sonnet / go cheaper" voice override; always Opus).
- **BLOCKED rung:** the user asked whether the SDD BLOCKED "needs more reasoning"
  case is a reason to escalate to a dynamic workflow — answer adopted as yes.
  Once everything is Opus, "re-dispatch with a more capable model" is a dead end;
  it becomes "escalate the leaf to a dynamic workflow."
- **Cross-harness:** Claude-Code-only. The user said: "i only care about CC ...
  that's tech debt. i dont care what happens to the others." No fallback carried
  for Codex/Gemini/Copilot/opencode/cursor.
- **Leaf-vs-composition framing (the user's reframe):** native workflows are for
  *leaf/subtasks* currently done by a single agent when complex — NOT for
  replacing existing composition nodes. "i'm not thinking we replace existing
  composition nodes. just leafy work that is currently only done by a single
  agent."
- **Scope of leaf wiring:** implement the high + medium tier (ranked #1–#7), with
  every medium one complexity/BLOCKED-gated (not default-on).
- **Pattern home:** a NEW skill (`escalating-to-workflows`) holds the reusable
  criteria/trigger/shapes; leaf sites point at it rather than restating.

## How the ranking + criteria were produced

A 6-agent dynamic workflow (the user explicitly opted into orchestration:
"maybe ask a subagent or do a workflow for it") enumerated all 20 dispatch sites
across the skills (12 genuine leaves), developed the escalation criteria in
parallel, and ranked the leaves by worthwhile-to-upgrade. The spec's three-gate
rule, signal lists, workflow-shape templates, and the #1–#12 ranking are the
distilled output of that workflow.

## Explicit non-goals

- No changes to composition nodes or human gates.
- Leaves #8/#9 (document reviewers — already escalated as burndown-reviews),
  #10/#11 (implementer-fixers — subsumed by #1), #12 (pressure-scenario
  subagent — a measurement instrument) are deliberately left single-agent.
- No config files / env vars / settings.json keys.
- No cross-harness adapter updates.
