# Opus Subagents + Leaf Workflow Escalation

Force every subagent in the superpowers fork to Opus (removing the cheaper-model
tiering and the cheaper-fixer override), with one deliberate exception — the
burndown reviewer pair stays Opus + Sonnet for cross-model diversity. Then add a
new, reusable pattern for selectively upgrading a *complex leaf task* from a
single-agent dispatch to a native Claude Code dynamic Workflow, and wire that
pattern into the seven dispatch sites where it is worthwhile.

## Motivation

Two changes, one theme: spend model capability where it pays off.

**Opus everywhere (with one carve-out).** The fork's daily driver is Opus. The
old "use the least powerful model that can handle each role" tiering in
subagent-driven-development (SDD) and the "go cheaper for the fixer" override in
burndown-reviews are cost optimizations that no longer match how the fork is
used, and they add decision surface and text that drifts. Forcing Opus removes
that surface. The one place a *different* model genuinely adds value is the
burndown reviewer pair: running Opus and Sonnet concurrently buys real
cross-*model* diversity (two architectures disagree in ways two Opus samples do
not), which is the entire point of that pass. That pair keeps Sonnet.

**Leaf escalation to dynamic workflows.** Today many "leaf" tasks — implement
one plan task, review one diff, apply one fix list — are done by a single
subagent in one shot. When such a leaf is genuinely *complex*, a single agent
can silently drop an interacting constraint, commit to the first plausible
design without surveying alternatives, or stop a discovery search early. Claude
Code's native dynamic Workflows (`parallel()` / `pipeline()` / `agent()` with
schema-validated output, adversarial verification, judge panels, loop-until-dry)
are built to research-then-implement-then-verify exactly this kind of work to a
higher bar. The opportunity is to upgrade the *leaf* — the unit of work — while
leaving the surrounding composition (the loops, fan-outs, and human gates that
give the skills their value) completely untouched.

## Mental model: leaves vs. composition

- A **composition node** is orchestration: a loop, a parallel fan-out across N
  independent problems, or a human-gated review gate. These are the skills'
  structure. **They are not changed by this work.** Native Workflows are a poor
  fit here because they run to completion in the background and cannot pause for
  the human input these nodes depend on.
- A **leaf** is a spot where a skill dispatches a *single* `Task` to do one unit
  of work. This is the upgrade target. When a leaf is complex, the single-agent
  dispatch is replaced (behind a gate) with a dynamic Workflow that returns the
  *same artifact shape* the single agent would have. The result re-enters the
  composition at exactly the point the single agent's result would have, and
  still flows through every existing review gate.

The rule, stated once: **at a leaf, if the work is complex, dispatch a Workflow
instead of a single agent. Composition unchanged; only the leaf's internal
quality bar goes up.**

## Scope

This spec covers:

- Model changes in `subagent-driven-development` and `burndown-reviews`.
- A new shared skill, `escalating-to-workflows`, holding the escalation criteria,
  trigger, workflow-shape templates, and return-shape contract rule.
- Wiring the escalation pattern into seven leaf dispatch sites (ranked #1–#7).
- Registration of the new skill in the plugin/marketplace manifests.
- Tests / verification consistent with the fork's existing test conventions.

This spec does **not** cover:

- Any change to composition nodes (the SDD per-task loop, the burndown
  round-loop, the dispatching-parallel-agents fan-out, any human gate).
- Cross-harness fallback. This work is Claude-Code-only by decision; the
  Codex/Gemini/Copilot/opencode/cursor adapters are not updated and may lose
  parity. That is accepted tech debt.
- The four leaves ranked not-worthwhile (document reviewers, the two
  implementer-fixers, the pressure-scenario subagent) — see "Explicitly out of
  scope" below.
- Config files, env vars, or `settings.json` keys. Behavior is governed by the
  skills' text and the orchestrator's judgment.

## Part A — Model changes

### A1. SDD `Model Selection` section

Replace the existing tiering guidance (cheap → standard → most-capable, with
per-task complexity signals) with: **all SDD subagents run Opus.** The
implementer, spec-compliance reviewer, code-quality reviewer, and final reviewer
all use Opus. Remove the "Task complexity signals" table that mapped file-count
to model tier; it no longer selects anything.

### A2. SDD BLOCKED-handling rung

The BLOCKED sub-case "if the task requires more reasoning, re-dispatch with a
more capable model" is a dead end once every subagent is Opus (there is nothing
more capable to escalate to). Replace that rung with: **escalate the leaf to a
dynamic workflow** (see Part B / `escalating-to-workflows`). The other BLOCKED
sub-cases (context problem → provide context and re-dispatch; task too large →
break into smaller pieces; plan wrong → escalate to human) are unchanged, except
that "task too large" may also be served by a pipeline-shaped workflow and
should cross-reference the new skill.

### A3. burndown-reviews fixer model

The fixer currently defaults to Opus but carries a voice tunable
("use sonnet for fixer this round", "go cheaper for the fixer"). **Remove that
override.** The fixer is always Opus. Concretely:

- In the loop init, `fixer_model_for_stage = opus` becomes a fixed value with no
  "overridable by user voice" qualifier.
- Delete the per-pause-point voice-override check (the precondition paragraph
  before round 1 / each disagreement-pause / round-8 hard-escalate) *as it
  pertains to the fixer model*. The other voice tunables ("run more rounds",
  "skip burndown") are unaffected.
- Delete the "Override the fixer model" bullet under "Voice tunables".
- Update the `burndown-fixer` agent description, the `burndown-reviews`
  frontmatter, and any inputs list that says `fixer_model` is "overridable by
  user voice" to state it is always Opus. The `fixer_model` input MAY be retained
  as a fixed `opus` for call-site clarity, or removed entirely if cleaner; either
  is acceptable, but no code path may set it to anything other than Opus.

### A4. Reviewer-pair carve-out (explicitly preserved)

The burndown reviewer pair (step A and the round-8 inventory pass) **keeps
`model="opus"` + `model="sonnet"`.** State this carve-out explicitly in the
burndown-reviews skill so a future reader does not "consistency-fix" it to
all-Opus: the cross-*model* diversity is the reason the pair exists. The
`burndown-reviewer` agent description's "Opus + Sonnet" framing is retained.

## Part B — New skill: `escalating-to-workflows`

A new skill at `skills/escalating-to-workflows/SKILL.md`. It is a *reference /
process* skill invoked by other skills (and usable directly), not a primary
user-facing entry point. It holds the pattern so no leaf site duplicates it.

### B1. The three-gate decision rule

A leaf is escalated from single-agent to a dynamic Workflow **only if all three
gates pass:**

1. **ELIGIBLE** — the leaf is self-contained with *no human gate inside it*, and
   a Workflow can be schema-constrained to return an artifact *shape-compatible*
   with what the single agent returned (so the consuming composition node is
   unchanged).
2. **HARD** — it exhibits irreducible complexity (dense *interacting*
   constraints, not mere line count) **OR** a wide consequential solution space
   **OR** an unknown-size discovery search — **AND** there is no cheap
   deterministic oracle (test/compile/typecheck) that already proves correctness.
3. **WORTH IT** — a wrong answer has high blast radius or low reversibility, OR
   the leaf is on the critical path, so the expected cost of a defect exceeds the
   Workflow's token + latency premium (roughly 5–20× a single shot).

**Default is single-agent.** Escalation is the exception, never the norm.

### B2. The empirical trigger (preferred)

Predicting complexity up front is unreliable. The preferred trigger is
*empirical*: dispatch the leaf single-agent first (the cheap common path), and
escalate the **same** leaf to a Workflow only on a demonstrated-difficulty
return — `BLOCKED`, low confidence, failed-its-own-tests after N attempts, or an
explicit "I see multiple viable approaches and can't decide." This reserves the
premium for leaves that prove they need it. Up-front escalation (skipping the
single-agent attempt) is permitted only when the HARD + WORTH-IT signals are
obvious and strong before dispatch.

### B3. Workflow-shape templates (match shape to reason)

- **Interacting-constraint complexity** → `research → implement →
  adversarial-verify` pipeline.
- **Wide consequential solution space** → `parallel()` competing implementers →
  judge panel → synthesize.
- **Unknown-size discovery search** → loop-until-dry (keep dispatching until a
  pass surfaces nothing new).

### B4. Return-shape contract rule

The composition node consuming the leaf is intentionally untouched, so the
Workflow's final stage **must be a shaping agent** that emits *exactly* the
return contract the single agent produced (status enum, severity-categorized
verdict, summary fields — whatever the call site expects). Richer internal
reasoning is fine; the emitted contract must be a drop-in. A
richer-but-incompatible output is a regression, not an upgrade.

### B5. Escalate-signals and anti-signals

Include the full signal lists as guidance (condensed):

- **Escalate when:** irreducible interacting-constraint complexity; adversarial
  cross-check materially reduces defect risk (security, auth, money/quota,
  migrations, cache-invalidation, silent-corruption modes); wide+consequential
  solution space; unknown-size enumeration; high blast radius + low
  reversibility; on the critical path; empirically BLOCKED.
- **Stay single-agent when:** large-but-mechanical / low-entropy; a cheap
  deterministic oracle already proves correctness; low blast radius +
  reversible; purely sequential with no branch points; latency-critical
  interactive path; contains an unavoidable human gate; return shape cannot be
  made compatible.

### B6. Opt-in / invocation note

Native Workflows require explicit user opt-in. A skill's instructions telling the
agent to use a Workflow *is* a valid opt-in (per the Workflow tool's own rules),
so a leaf site escalating per this skill is legitimate. The skill should state
this so an implementer does not add a redundant "ask the user first" gate.

## Part C — Wiring the seven leaf sites

Each wiring adds an escalation *option behind a gate*; single-agent remains the
default path. Each points at `escalating-to-workflows` rather than restating the
criteria.

| # | Leaf | Skill | Wiring |
|---|------|-------|--------|
| 1 | Implementer subagent | SDD | **Flagship.** BLOCKED-escalation: single first; on BLOCKED / DONE_WITH_CONCERNS / can't-decide, re-dispatch the *same* task as `research → implement → adversarial-verify` (TDD inner loop). Final shaping agent re-emits the DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT status contract. This *is* the Part-A2 BLOCKED rung's replacement. |
| 2 | code-reviewer subagent | requesting-code-review | Escalate to `parallel()` multi-model reviewers (Opus + Sonnet) over the same BASE..HEAD range → judge/reconcile → one merged severity-categorized verdict matching the single-agent shape. |
| 3 | Final code reviewer | SDD | Panel + loop-until-dry enumeration sweep over the whole-branch diff → judge → one consolidated Strengths / Issues / Assessment report. Highest blast-radius review point. |
| 4 | Code-quality reviewer (per task) | SDD | **Mostly inherited from #2** — it reuses the `code-reviewer.md` template. Add only a short pointer note; gated on a per-task complexity/BLOCKED signal, not default-on. |
| 5 | Spec-compliance reviewer | SDD | Short complexity-gated pointer: on a hard spec, `research (re-read spec + code) → adversarial verify enumerating each requirement → emit compliant/issues list`. |
| 6 | Fixer (step F) | burndown-reviews | Complexity-gated pointer, **impl-stage substantive fixes only**: `research → apply → self-verify-against-findings` → emit the exact deferred-IDs / created / deleted / summary contract. Mechanical findings (typo/format) stay single-agent. Retry-once + crash-abort semantics preserved. |
| 7 | Per-domain fixer | dispatching-parallel-agents | BLOCKED-gated pointer on the *individual leaf* (not the fan-out, which stays a composition): single first; on can't-find-root-cause / repeated failures, re-dispatch the same domain as `systematic-debug → fix → verify`, emitting the same root-cause + changes summary. |

**Shared-template note for #2/#4:** because the SDD code-quality reviewer
dispatches the `spandapowers:code-reviewer` subagent type built from
`requesting-code-review/code-reviewer.md`, upgrading #2 at the template level
delivers most of #4 automatically. The implementation should make the escalation
guidance live with the shared `code-reviewer` material so both sites inherit it,
and #4's edit is just a gate-and-pointer.

## Part D — Explicitly out of scope (left as single-agent)

- **#8 spec document reviewer (brainstorming)** and **#9 plan document reviewer
  (writing-plans)** — already escalated *as* `burndown-reviews` (the multi-model
  loop is literally the escalated form of document review). Re-wrapping the bare
  template would double-count. No change.
- **#10 implementer fixes spec gaps** and **#11 implementer fixes quality
  issues** (SDD) — known, enumerated, scoped fix lists; the surrounding
  re-review loop already verifies them, and they are subsumed by the #1
  implementer upgrade. No separate wiring.
- **#12 pressure-scenario subagent (writing-skills)** — a *measurement
  instrument*. Its validity depends on being a single clean observed agent;
  wrapping it in a verify-and-fix workflow would contaminate the very behavior it
  measures. Left untouched.
- All composition nodes (per-task loop, burndown round-loop, parallel fan-out,
  human gates) — untouched by definition.

## Part E — Verification

- **No stray cheaper-model references:** after the edits, the only surviving
  Sonnet / non-Opus references in skills and agents are the deliberate burndown
  reviewer-pair carve-out (Part A4). Grep to confirm; anything else is a bug.
- **Skill registration:** the new `escalating-to-workflows` skill must be
  registered wherever the catalog/manifest lists skills (e.g.
  `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json`), matching the
  pattern the existing skills use.
- **Skill-triggering tests:** the fork ships a skill-triggering test suite. The
  new skill's frontmatter `name` and `description` must be consistent with how
  that suite expects skills to be discoverable; add a triggering entry if the
  suite enumerates skills.
- **Burndown fixtures:** confirm the fixer-model-override removal does not break
  the existing `tests/burndown-reviews/` fixtures or the manual-verification
  procedure (which references Sonnet only in the *reviewer* context, which is
  preserved).
- **Internal consistency:** every leaf-site edit references
  `escalating-to-workflows` rather than restating the criteria; no leaf site adds
  a redundant human-opt-in gate (Part B6).

## Implementation note (pre-flight)

The working tree currently carries uncommitted modifications to several skills,
including some this work edits (`subagent-driven-development/SKILL.md`,
`requesting-code-review/SKILL.md`, `writing-skills/SKILL.md`, and others). Before
implementation begins, the working tree must be reconciled (committed or stashed)
so the impl diff is attributable and the SDD/burndown pre-flight clean-tree check
passes. This is a precondition, not part of the change itself.

## Open questions

None blocking. The `fixer_model` input retain-vs-remove choice (A3) is left to
implementation discretion within the stated constraint.
