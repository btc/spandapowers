# Opus Subagents + Leaf Workflow Escalation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use spandapowers:subagent-driven-development (recommended) or spandapowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Force all subagents to Opus (except the deliberate Opus+Sonnet review carve-outs), add a new `escalating-to-workflows` skill, and wire leaf→workflow escalation into seven dispatch sites.

**Architecture:** This is a documentation/skill-content change — every task edits markdown skill files or agent definitions; no executable code. The new skill holds the escalation pattern; seven leaf sites point at it rather than duplicating it. Composition nodes (loops, fan-outs, human gates) are untouched.

**Tech Stack:** Markdown skill files (`skills/*/SKILL.md`, prompt templates, `agents/*.md`). Verification is grep-based content assertions plus the existing bash test harness (`tests/skill-triggering/run-all.sh`, `tests/burndown-reviews/`) — there is no pytest in this repo.

**Spec:** `docs/superpowers/specs/2026-06-04-opus-subagents-and-leaf-workflow-escalation-design.md`

**Pre-flight (do once before Task 1):** The working tree must be clean. The rename sweep is already committed (`9972e5e`) and the `TODO` file removed; confirm with `git status --porcelain` (expect empty output). If not empty, stop and reconcile before starting.

---

### Task 1: New skill — `escalating-to-workflows`

This is foundational: every later leaf-site task points at this skill. It embodies spec Part B (B1–B6).

**Files:**
- Create: `skills/escalating-to-workflows/SKILL.md`

- [ ] **Step 1: Create the skill directory and file**

Create `skills/escalating-to-workflows/SKILL.md` with exactly this content:

````markdown
---
name: escalating-to-workflows
description: Use when a single subagent leaf task (implement one task, review one diff, apply one fix list) is complex enough that a one-shot dispatch is likely to drop a constraint, pick the first plausible design, or stop a search early — escalate that leaf to a native Claude Code dynamic Workflow instead. Provides the escalation criteria, the empirical trigger, workflow-shape templates, and the return-shape contract. Invoked by other skills at their leaf dispatch sites; not a user-facing entry point.
---

# Escalating a Leaf to a Dynamic Workflow

## Overview

A **leaf** is a spot where a skill dispatches a *single* `Task` to do one unit of work. A **composition node** is orchestration (a loop, a fan-out, a human gate). This skill is about leaves only — never escalate a composition node, and never put a human gate inside an escalated leaf (background Workflows run to completion and cannot pause for input).

The rule: **at a leaf, if the work is complex, dispatch a Workflow instead of a single agent.** The Workflow researches → implements → verifies the leaf to a higher bar and returns the *same artifact shape* the single agent would have, so the surrounding composition is unchanged. **Default is single-agent. Escalation is the exception.**

## When to escalate — the empirical trigger (primary)

Predicting complexity up front is unreliable. The preferred trigger is *empirical*: dispatch the leaf single-agent first, and escalate the **same** leaf to a Workflow only on a demonstrated-difficulty return. "Demonstrated difficulty" is leaf-type-aware:

- **Implementer leaf** — a `BLOCKED` return, a failed-its-own-tests result, or an explicit "I see multiple viable approaches and can't decide."
- **Fixer leaf** — its existing retry oracle is exhausted (retry-once spent / can't-find-root-cause after the suite still fails). `N` is not a new global constant; each site delegates to its own retry semantics, defaulting to "after the first failed self-test" where no counter exists.
- **Reviewer leaf** — reviewers emit a verdict, not a pass/fail self-test, so they have no implementer-style oracle. They are **primarily discretionary-gated** (the up-front path below), with a reviewer-emitted low-confidence / can't-reconcile signal as the only empirical fallback.

## When to escalate — up-front (judgment guidance, subordinate to the empirical trigger)

Skipping the single-agent attempt is permitted **only when at least two signals from the HARD subset below are present simultaneously before dispatch** (any two of the three suffice; no specific combination required). Otherwise use the empirical path.

The three-gate rule structures that judgment call. Escalate up-front only if **all three** pass:

1. **ELIGIBLE** — self-contained, *no human gate inside it*, and a Workflow can be schema-constrained to return an artifact *shape-compatible* with the single-agent output.
2. **HARD** — irreducible interacting-constraint complexity (e.g. ≥3 requirements that constrain each other) **OR** a wide consequential solution space **OR** an unknown-size discovery search — **AND** no cheap deterministic oracle (test/compile/typecheck) already proves correctness.
3. **WORTH IT** — high blast radius or low reversibility, or on the critical path, so the expected defect cost exceeds the Workflow's token+latency premium (roughly 5–20× a single shot).

These gates are judgment guidance / tie-breakers, not a rigid rubric.

## Signal lists

**Escalate when** (grouped by which gate the signal serves):
- *HARD-gate:* irreducible interacting-constraint complexity; wide + consequential solution space; unknown-size enumeration.
- *WORTH-IT-gate:* adversarial cross-check materially reduces defect risk (security, auth, money/quota, migrations, cache-invalidation, silent-corruption modes); high blast radius + low reversibility; on the critical path.
- *Empirical trigger* (not a HARD signal): the leaf returned empirically `BLOCKED` (or its leaf-type equivalent). Belongs to the empirical path, not the up-front HARD subset.

**Stay single-agent when:** large-but-mechanical / low-entropy; a cheap deterministic oracle already proves correctness; low blast radius + reversible; purely sequential with no branch points; latency-critical interactive path; contains an unavoidable human gate; the return shape cannot be made compatible.

## Workflow-shape templates (match shape to reason)

- **Interacting-constraint complexity** → `research → implement → adversarial-verify` pipeline.
- **Wide consequential solution space** → `parallel()` competing implementers → judge panel → synthesize.
- **Unknown-size discovery search** → loop-until-dry (keep dispatching until a pass surfaces nothing new).

When the escalation is purely **empirical** (a `BLOCKED` / failed-test return with no identified complexity type), default to the `research → implement → adversarial-verify` pipeline unless the signal points to a specific root cause (e.g. an explicit "many viable approaches" selects the `parallel()` competing-implementers → judge shape).

The internal inter-stage contracts of each shape are the orchestrator's to define when authoring the Workflow at runtime. The only **contractual** output is the final stage's return shape (see below). Do not pre-specify per-stage schemas.

## Return-shape contract

The composition consuming the leaf is intentionally untouched, so the Workflow's **final stage must be a shaping agent** that emits *exactly* the return contract the single agent produced (status enum, severity-categorized verdict, summary fields — whatever the call site expects). Richer internal reasoning is fine; the emitted contract must be a drop-in. A richer-but-incompatible output is a regression, not an upgrade.

## Opt-in note

Native Workflows require explicit user opt-in. Per current Workflow tool behavior, a skill whose instructions tell the agent to use a Workflow counts as opt-in — so escalating per this skill is legitimate; **do not add a redundant "ask the user first" gate.** Verify this still holds at implementation time. **Fallback:** if skill-instruction opt-in is no longer sufficient under the tool's then-current rules, add a one-time user confirmation at the *first* escalation in a session (not per-escalation) and document that behavior here.
````

- [ ] **Step 2: Verify the file exists with valid frontmatter**

Run: `head -4 skills/escalating-to-workflows/SKILL.md`
Expected: shows the `---` / `name: escalating-to-workflows` / `description:` / `---` frontmatter block.

Run: `grep -c "^name: escalating-to-workflows$" skills/escalating-to-workflows/SKILL.md`
Expected: `1`

- [ ] **Step 3: Confirm no manifest edit is needed (negative check)**

Run: `git status --porcelain .claude-plugin/`
Expected: empty output (the manifests must NOT be touched — skills are auto-discovered from `skills/`).

- [ ] **Step 4: Commit**

```bash
git add skills/escalating-to-workflows/SKILL.md
git commit -m "feat: add escalating-to-workflows skill"
```

---

### Task 2: SDD `Model Selection` → all Opus (spec A1)

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md:101-114`

- [ ] **Step 1: Replace the Model Selection section**

Replace lines 101–114 (the `## Model Selection` heading through the "Task complexity signals" list) with:

```markdown
## Model Selection

All SDD subagents run **Opus** — the implementer, the spec-compliance reviewer, the code-quality reviewer, and the final reviewer. There is no cheaper/faster tier and no per-task model selection.

When a leaf is genuinely complex, the lever is not a bigger model (there isn't one) — it is escalating that leaf to a dynamic Workflow. See spandapowers:escalating-to-workflows.
```

- [ ] **Step 2: Verify the tiering text is gone and Opus text is present**

Run: `grep -nE "least powerful model|cheap model|standard model|Task complexity signals" skills/subagent-driven-development/SKILL.md`
Expected: no matches (exit code 1).

Run: `grep -c "All SDD subagents run \*\*Opus\*\*" skills/subagent-driven-development/SKILL.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: SDD subagents always use Opus"
```

---

### Task 3: SDD BLOCKED rung + #1 controller wiring (spec A2, Part C #1)

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md:122,126-130` (DONE_WITH_CONCERNS handling + BLOCKED rung)

- [ ] **Step 1: Replace BLOCKED rung 2 with workflow escalation**

In the `## Handling Implementer Status` section, replace the BLOCKED list (current lines 126–130):

```markdown
**BLOCKED:** The implementer cannot complete the task. Assess the blocker:
1. If it's a context problem, provide more context and re-dispatch with the same model
2. If the task requires more reasoning, re-dispatch with a more capable model
3. If the task is too large, break it into smaller pieces
4. If the plan itself is wrong, escalate to the human
```

with:

```markdown
**BLOCKED:** The implementer cannot complete the task. Assess the blocker:
1. If it's a context problem, provide more context and re-dispatch (still Opus)
2. If the task requires more reasoning, escalate the **same leaf** to a dynamic Workflow — there is no more capable model than Opus, so the lever is multi-agent decomposition. See spandapowers:escalating-to-workflows.
3. If the task is too large, break it into smaller pieces (a pipeline-shaped Workflow over the pieces is also an option — see spandapowers:escalating-to-workflows)
4. If the plan itself is wrong, escalate to the human
```

- [ ] **Step 2: Add the DONE_WITH_CONCERNS / can't-decide escalation entry points**

Replace the `**DONE_WITH_CONCERNS:**` paragraph (current line 122):

```markdown
**DONE_WITH_CONCERNS:** The implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations (e.g., "this file is getting large"), note them and proceed to review.
```

with:

```markdown
**DONE_WITH_CONCERNS:** The implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations (e.g., "this file is getting large"), note them and proceed to review. If the doubts are substantive — or the implementer signalled it couldn't decide among multiple viable approaches — that is an empirical escalation entry point for the #1 implementer leaf: re-dispatch the **same** task as a dynamic Workflow (see spandapowers:escalating-to-workflows). DONE_WITH_CONCERNS and can't-decide are additional empirical entry points wired here at the implementer leaf — distinct from the BLOCKED rung above; do not fold them into BLOCKED handling.
```

- [ ] **Step 3: Verify**

Run: `grep -nE "more capable model" skills/subagent-driven-development/SKILL.md`
Expected: no matches (exit code 1) — the dead rung is gone.

Run: `grep -c "escalating-to-workflows" skills/subagent-driven-development/SKILL.md`
Expected: `≥3` (Model Selection from Task 2, plus the two rungs here).

- [ ] **Step 4: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: SDD BLOCKED/concerns rungs escalate leaf to dynamic workflow"
```

---

### Task 4: Implementer-prompt escalation text (spec A2, Part C #1)

**Files:**
- Modify: `skills/subagent-driven-development/implementer-prompt.md:69-72`

- [ ] **Step 1: Update the "How to escalate" blurb**

Replace lines 69–72:

```markdown
    **How to escalate:** Report back with status BLOCKED or NEEDS_CONTEXT. Describe
    specifically what you're stuck on, what you've tried, and what kind of help you need.
    The controller can provide more context, re-dispatch with a more capable model,
    or break the task into smaller pieces.
```

with:

```markdown
    **How to escalate:** Report back with status BLOCKED or NEEDS_CONTEXT (or
    DONE_WITH_CONCERNS if you finished but couldn't decide among viable approaches).
    Describe specifically what you're stuck on, what you've tried, and what kind of
    help you need. The controller can provide more context, escalate this same task
    to a dynamic multi-agent Workflow, or break the task into smaller pieces.
```

- [ ] **Step 2: Verify**

Run: `grep -nE "more capable model" skills/subagent-driven-development/implementer-prompt.md`
Expected: no matches (exit code 1).

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/implementer-prompt.md
git commit -m "feat: implementer-prompt escalation points to dynamic workflow"
```

---

### Task 5: burndown-reviews fixer-model override removal (spec A3) + reviewer-pair carve-out note (A4a)

**Files:**
- Modify: `skills/burndown-reviews/SKILL.md` — lines 21, 37–38, 43, 45 (step A), 58 (step D), 60 (step F), 90 (Voice tunables)

Apply these surgical edits. Each removes only the fixer-model-override clause; preserve all surrounding loop-structure content.

- [ ] **Step 1: Inputs list (line 21)**

Replace:
```markdown
- `fixer_model` — `opus` for all stages. Overridable by user voice.
```
with:
```markdown
- `fixer_model` — always `opus` for all stages. Retained as a fixed symbolic constant for call-site traceability and minimal diff; **not** a tunable parameter — no code path may set it to anything other than `opus`.
```

- [ ] **Step 2: Loop init (lines 37–38)**

Replace:
```
fixer_model_for_stage = opus   # all stages; overridable by user voice
   # (last-write wins — see "Voice tunables")
```
with:
```
fixer_model_for_stage = opus   # fixed for all stages; not tunable
```

- [ ] **Step 3: Voice-override precondition paragraph (line 43)**

This combined paragraph is entirely fixer-override content EXCEPT its final loop-structure sentence. Replace the whole line-43 paragraph:

```markdown
**Voice-override check (precondition for round 1, each disagreement-pause, and round-8 hard-escalate):** before dispatching reviewers in round 1 — and again before re-entering step E in any round, and during the round-8 hard-escalate exchange — listen for a fixer-model voice override (e.g., "use sonnet for fixer this round", "switch fixer to opus"). Last-write wins; update `fixer_model_for_stage` immediately. This is a per-pause-point check, not a per-round step. The plan's loop steps below are labeled to match the spec pseudocode's letters (A through F-bis), with the same operations and ordering.
```
with (loop-structure sentence preserved, override content removed):
```markdown
The loop steps below are labeled to match the spec pseudocode's letters (A through F-bis), with the same operations and ordering.
```

- [ ] **Step 4: Step A reviewer-pair carve-out note (line 45)**

Append a carve-out note to the end of the step-A bullet (after "...into `all_findings`."). Add this sentence:
```markdown
 (**Deliberate carve-out — do not "consistency-fix":** the `opus`+`sonnet` pairing is intentional cross-*model* review diversity, the entire reason the pair exists. This is the only reviewer-pair Sonnet usage and it stays.)
```

- [ ] **Step 5: Step D (line 58)**

Replace the opening of the step-D bullet:
```markdown
4. **(D) Pause if any escalated disagreements remain** — re-check the fixer-model voice override at this pause. Surface disagreements to the user in plain language, batched per round.
```
with (override re-check removed, disagreement-pause logic preserved):
```markdown
4. **(D) Pause if any escalated disagreements remain** — surface disagreements to the user in plain language, batched per round.
```

- [ ] **Step 6: Step F (line 60)**

Replace:
```markdown
6. **(F) Dispatch the fixer subagent** — single Task call with the `burndown-fixer` agent and `model=fixer_model_for_stage` (the current value, after any voice override). Pass `artifact_path`, the reconciled `fix_list`, and `stage` (plus `diff_paths` and `diff_base` for impl).
```
with:
```markdown
6. **(F) Dispatch the fixer subagent** — single Task call with the `burndown-fixer` agent and `model=fixer_model_for_stage` (always `opus`). Pass `artifact_path`, the reconciled `fix_list`, and `stage` (plus `diff_paths` and `diff_base` for impl).
```

- [ ] **Step 7: Voice tunables — delete the override bullet (line 90)**

Delete the entire bullet:
```markdown
- **Override the fixer model** — listen for phrases like "use sonnet for fixer this round", "switch fixer to opus", "go cheaper for the fixer". Detected at three points: (i) at the start of round 1, before the first reviewer dispatch; (ii) on each disagreement-pause; (iii) during the round-8 hard-escalate exchange. Last-write wins. Update `fixer_model_for_stage` immediately; the new value applies to all subsequent fixer dispatches.
```
(Leave the "Run more rounds" bullet and the "skip burndown" paragraph intact.)

- [ ] **Step 8: Verify the override is gone everywhere but the reviewer pair survives**

Run: `grep -niE "voice override|overridable|go cheaper|use sonnet for fixer|switch fixer" skills/burndown-reviews/SKILL.md`
Expected: no matches (exit code 1).

Run: `grep -c 'model="sonnet"' skills/burndown-reviews/SKILL.md`
Expected: `≥1` (the reviewer pair in step A — and the round-8 inventory pass, which says "same inputs as in step A" — preserved).

Run: `grep -c "Deliberate carve-out" skills/burndown-reviews/SKILL.md`
Expected: `1`

- [ ] **Step 9: Commit**

```bash
git add skills/burndown-reviews/SKILL.md
git commit -m "feat: burndown fixer always Opus; document reviewer-pair carve-out"
```

---

### Task 6: burndown-fixer agent description (spec A3)

**Files:**
- Modify: `agents/burndown-fixer.md:4` (the `description` frontmatter)

- [ ] **Step 1: Update the description**

Replace the description line:
```markdown
  Applies a reconciled finding list to a Superpowers-driven artifact. Dispatched by the burndown-reviews skill; the orchestrator picks the model at dispatch time (opus for all stages; overridable by user voice).
```
with:
```markdown
  Applies a reconciled finding list to a Superpowers-driven artifact. Dispatched by the burndown-reviews skill; the orchestrator dispatches it with Opus for all stages (the fixer model is always Opus and is not tunable).
```

- [ ] **Step 2: Verify**

Run: `grep -niE "overridable|picks the model" agents/burndown-fixer.md`
Expected: no matches (exit code 1).

- [ ] **Step 3: Confirm the reviewer agent is deliberately untouched**

Run: `git status --porcelain agents/burndown-reviewer.md`
Expected: empty (its "Opus + Sonnet" framing is the A4a carve-out and stays unchanged).

- [ ] **Step 4: Commit**

```bash
git add agents/burndown-fixer.md
git commit -m "feat: burndown-fixer description states always-Opus"
```

---

### Task 7: Shared code-reviewer escalation pointer (spec Part C #2/#4, A4b)

This is the shared template both #2 and #4 inherit. Editing it here delivers most of #4 automatically.

**Files:**
- Modify: `skills/requesting-code-review/code-reviewer.md` (append a section after line 108, before `## Example Output`)

- [ ] **Step 1: Add an escalation section to the shared template**

Insert before the `## Example Output` heading:

```markdown
## Escalating a Complex Review

This reviewer is a **Family II (discretionary review-gated) leaf** (see spandapowers:escalating-to-workflows). It emits a verdict, not a pass/fail self-test, so it does **not** use a `BLOCKED` return. Escalate this single-reviewer dispatch to a dynamic Workflow only when the diff is high-blast-radius / large (orchestrator complexity judgment) **or** a single reviewer returns a low-confidence / can't-reconcile signal — not by default.

On escalation: run `parallel()` multi-model reviewers (**Opus + Sonnet** — a deliberate review-diversity carve-out, the only non-Opus model permitted here) over the same `BASE_SHA..HEAD_SHA` range → judge/reconcile → emit **one merged** severity-categorized verdict in exactly the Output Format above (the single-agent shape). See spandapowers:escalating-to-workflows for the gate and the shaping-agent contract.
```

- [ ] **Step 2: Verify**

Run: `grep -c "escalating-to-workflows" skills/requesting-code-review/code-reviewer.md`
Expected: `≥1`

Run: `grep -c "Opus + Sonnet" skills/requesting-code-review/code-reviewer.md`
Expected: `1` (the A4b carve-out).

- [ ] **Step 3: Commit**

```bash
git add skills/requesting-code-review/code-reviewer.md
git commit -m "feat: code-reviewer template gains workflow-escalation pointer (#2/#4)"
```

---

### Task 8: requesting-code-review #2 gate-and-pointer (spec Part C #2)

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md` (add a short note in the `## How to Request` flow, after line 41)

- [ ] **Step 1: Add the pointer after the placeholder list**

Insert after the `{DESCRIPTION}` placeholder bullet (line 41), before `**3. Act on feedback:**`:

```markdown
**Complex diffs:** this single-reviewer dispatch is a Family II leaf. For a high-blast-radius / large diff, or when a single reviewer returns low confidence, escalate it to a multi-model review Workflow instead — see spandapowers:escalating-to-workflows and the "Escalating a Complex Review" section of `code-reviewer.md`. Single-reviewer is the default.
```

- [ ] **Step 2: Verify**

Run: `grep -c "escalating-to-workflows" skills/requesting-code-review/SKILL.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "feat: requesting-code-review points to workflow escalation (#2)"
```

---

### Task 9: SDD code-quality reviewer #4 gate-and-pointer (spec Part C #4)

#4 reuses `code-reviewer.md` (edited in Task 7), so this is just a gate-and-pointer — no escalation logic duplicated.

**Files:**
- Modify: `skills/subagent-driven-development/code-quality-reviewer-prompt.md` (append after the closing checks, before the final "Code reviewer returns:" line or at end)

- [ ] **Step 1: Add the pointer note at the end of the file**

Append to the end of `skills/subagent-driven-development/code-quality-reviewer-prompt.md`:

```markdown

**Escalation:** this is a Family II review leaf that reuses `requesting-code-review/code-reviewer.md`, so it inherits that template's "Escalating a Complex Review" guidance automatically. Escalate to a multi-model review Workflow only on a high-blast-radius / large diff or a reviewer low-confidence signal — never on a `BLOCKED` return (reviewers don't emit one), and not by default. See spandapowers:escalating-to-workflows.
```

- [ ] **Step 2: Verify**

Run: `grep -c "escalating-to-workflows" skills/subagent-driven-development/code-quality-reviewer-prompt.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/code-quality-reviewer-prompt.md
git commit -m "feat: SDD code-quality reviewer gate-and-pointer (#4)"
```

---

### Task 10: SDD final reviewer #3 (spec Part C #3)

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md` (add a short subsection immediately before `## Burndown Review Pass`, ~line 279)

- [ ] **Step 1: Add a "Final Review Escalation" note before the Burndown Review Pass section**

Insert immediately before the `## Burndown Review Pass` heading:

```markdown
## Final Review Escalation

The final whole-implementation code review (dispatched once after all per-task loops) is the highest-blast-radius review point in SDD. It is a Family II review leaf: escalate it to a dynamic Workflow on a large whole-branch diff (orchestrator complexity judgment) or a reviewer low-confidence / can't-reconcile signal — not a `BLOCKED` return, and not by default. On escalation: a multi-model panel (**Opus + Sonnet** — review-diversity carve-out) plus a loop-until-dry enumeration sweep over the whole-branch diff → judge → one consolidated Strengths / Issues / Assessment report (the single-agent shape). See spandapowers:escalating-to-workflows.

```

- [ ] **Step 2: Verify**

Run: `grep -c "Final Review Escalation" skills/subagent-driven-development/SKILL.md`
Expected: `1`

Run: `grep -c "escalating-to-workflows" skills/subagent-driven-development/SKILL.md`
Expected: `≥4` (Tasks 2, 3 ×2, and this one).

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat: SDD final reviewer escalation note (#3)"
```

---

### Task 11: SDD spec-compliance reviewer #5 (spec Part C #5)

**Files:**
- Modify: `skills/subagent-driven-development/spec-reviewer-prompt.md` (append after the closing code fence, line 61–62)

- [ ] **Step 1: Add a pointer note after the template fence**

Append to the end of `skills/subagent-driven-development/spec-reviewer-prompt.md` (after the closing ```` ``` ````):

```markdown

**Escalation:** this is a Family II review leaf. For a high-blast-radius or hard spec, or when the reviewer returns low confidence, escalate to a Workflow: `research (re-read spec + code) → adversarial verify enumerating each requirement → emit the compliant/issues list` (the single-agent shape). Not a `BLOCKED` return; not by default. See spandapowers:escalating-to-workflows.
```

- [ ] **Step 2: Verify**

Run: `grep -c "escalating-to-workflows" skills/subagent-driven-development/spec-reviewer-prompt.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add skills/subagent-driven-development/spec-reviewer-prompt.md
git commit -m "feat: SDD spec-compliance reviewer escalation note (#5)"
```

---

### Task 12: burndown fixer leaf #6 (spec Part C #6)

**Files:**
- Modify: `skills/burndown-reviews/SKILL.md` (add a note to the step-F bullet edited in Task 5, after its legitimacy rules — append after line 67, the "On fatal abort..." line)

- [ ] **Step 1: Add the #6 escalation note after step F's rules**

Immediately after the step-F "On fatal abort, set `abort_error`..." line (current line 67), add a new indented note:

```markdown
   - **Complex-fix escalation (Family I):** the fixer is a Family I leaf — escalate it to a dynamic Workflow only when its retry oracle is exhausted (retry-once spent and the artifact/suite still wrong), and only for **substantive impl-stage fixes**. Mechanical typo/format findings stay single-agent (B5 anti-signal "large-but-mechanical / low-entropy"). On escalation: `research → apply → self-verify-against-findings` → emit the exact `deferred` / `created_paths` / `deleted_paths` / summary contract. Retry-once + crash-abort semantics are preserved. See spandapowers:escalating-to-workflows.
```

- [ ] **Step 2: Verify**

Run: `grep -c "escalating-to-workflows" skills/burndown-reviews/SKILL.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add skills/burndown-reviews/SKILL.md
git commit -m "feat: burndown fixer leaf workflow escalation (#6)"
```

---

### Task 13: dispatching-parallel-agents per-domain fixer #7 (spec Part C #7)

**Files:**
- Modify: `skills/dispatching-parallel-agents/SKILL.md` (add a note in the `## Agent Prompt Structure` section)

- [ ] **Step 1: Add a per-leaf escalation note**

In `skills/dispatching-parallel-agents/SKILL.md`, locate the `## Agent Prompt Structure` section and append this paragraph at its end (before the next `##` heading):

```markdown
**Escalating a stubborn domain (per-leaf, not the fan-out):** the parallel fan-out itself stays a composition node — leave it. But an *individual* per-domain fixer leaf is a Family I leaf that may be escalated to a dynamic Workflow when it can't find the root cause: single-agent first, and on can't-find-root-cause / repeated failures (the suite still failing after the single-agent fix attempt — this fixer has no dedicated retry counter, so it uses the "after the first failed self-test" default), re-dispatch the **same** domain as `systematic-debug → fix → verify`, emitting the same root-cause + changes summary. See spandapowers:escalating-to-workflows.
```

- [ ] **Step 2: Verify**

Run: `grep -c "escalating-to-workflows" skills/dispatching-parallel-agents/SKILL.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add skills/dispatching-parallel-agents/SKILL.md
git commit -m "feat: dispatching-parallel-agents per-domain fixer escalation (#7)"
```

---

### Task 14: Verification sweep (spec Part E)

No new edits — this task runs the spec's Part E checks and the existing test harness.

**Files:**
- (read-only checks)

- [ ] **Step 1: No stray cheaper-model references in the edited file set**

Run:
```bash
grep -rniE "sonnet|cheaper model|least powerful|more capable model" \
  skills/subagent-driven-development/ \
  skills/burndown-reviews/ \
  skills/requesting-code-review/ \
  skills/escalating-to-workflows/ \
  agents/burndown-fixer.md agents/burndown-reviewer.md
```
Expected: the ONLY `sonnet` matches are the deliberate review carve-outs — (a) the burndown reviewer pair in `burndown-reviews/SKILL.md` step A + round-8 inventory and `agents/burndown-reviewer.md`'s "Opus + Sonnet" framing, and (b) the `Opus + Sonnet` carve-out text in `code-reviewer.md` / SDD final-reviewer note. There must be **no** "cheaper model", "least powerful", or "more capable model" matches anywhere in this set, and **no** "use sonnet for fixer" / "overridable" matches. Eyeball each `sonnet` hit and confirm it is a carve-out; any other is a bug — fix it before continuing.

- [ ] **Step 2: Confirm out-of-scope files were not touched**

Run: `git diff --name-only 9972e5e HEAD -- skills/writing-skills/ .claude-plugin/`
Expected: empty output (pre-existing model-tier references in `writing-skills/anthropic-best-practices.md` are out of scope; manifests must be untouched).

- [ ] **Step 3: New skill discoverable; not added to the triggering suite**

Run: `test -f skills/escalating-to-workflows/SKILL.md && echo OK`
Expected: `OK`

Run: `grep -c "escalating-to-workflows" tests/skill-triggering/run-all.sh`
Expected: `0` (reference skill is intentionally excluded from the curated user-facing suite).

- [ ] **Step 4: Skill-triggering suite still passes for the edited user-facing skills**

Run: `bash tests/skill-triggering/run-all.sh`
Expected: the suite passes (the edits are additive pointers and do not change which naive prompts trigger `requesting-code-review`, `dispatching-parallel-agents`, `burndown-reviews`, etc.). If the harness requires network/API access and cannot run in this environment, note that explicitly and fall back to confirming the `SKILLS=()` array is unchanged: `git diff 9972e5e HEAD -- tests/skill-triggering/run-all.sh` → empty.

- [ ] **Step 5: Burndown fixtures unaffected**

Run: `ls tests/burndown-reviews/` and read `tests/burndown-reviews/MANUAL-VERIFICATION.md`.
Expected: confirm the fixer-model-override removal does not contradict any fixture; the only Sonnet reference in the manual-verification doc is in the *reviewer* context (preserved). If a fixture asserts the old "overridable" fixer behavior, update it to match always-Opus and note the change.

- [ ] **Step 6: Internal consistency — every leaf site points at the new skill**

Run:
```bash
grep -rl "escalating-to-workflows" \
  skills/subagent-driven-development/ \
  skills/requesting-code-review/ \
  skills/burndown-reviews/ \
  skills/dispatching-parallel-agents/
```
Expected: at minimum `SKILL.md` + `implementer-prompt.md` + `code-quality-reviewer-prompt.md` + `spec-reviewer-prompt.md` under SDD, both files under requesting-code-review, `burndown-reviews/SKILL.md`, and `dispatching-parallel-agents/SKILL.md`. Confirm no leaf site restates the criteria instead of pointing, and none adds a redundant "ask the user first" gate (`grep -rn "ask the user first\|ask the human first" skills/` over the edited set → no new matches).

- [ ] **Step 7: Final commit (only if Step 5 required a fixture edit; otherwise skip)**

```bash
git add tests/burndown-reviews/
git commit -m "test: align burndown fixtures with always-Opus fixer"
```

---

## Notes for the implementer

- These are skill-content edits; "tests" are grep assertions and the existing bash harness, not pytest.
- Line numbers are anchors from the spec-writing session and may drift by ±a few lines after earlier tasks in this plan land; match on the quoted text, not the number.
- The `superpowers` → `spandapowers` rename is already committed (`9972e5e`); use `spandapowers:` in all new skill references.
- Do not touch: `.claude-plugin/*`, `agents/burndown-reviewer.md`, `skills/writing-skills/`, or any composition node (loops, fan-outs, human gates).
