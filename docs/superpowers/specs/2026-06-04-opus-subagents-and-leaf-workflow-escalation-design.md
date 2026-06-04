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
that surface. The places a *different* model genuinely adds value are **review**
leaves, where running Opus and Sonnet concurrently buys real cross-*model*
diversity (two architectures disagree in ways two Opus samples do not), which is
the entire point of those passes. Two deliberate carve-outs keep Sonnet, both
justified by that same cross-model review-diversity rationale: (a) the burndown
reviewer pair, and (b) the escalated multi-model review panels in the #2/#3 leaf
wirings (Part C). See A4.

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
- Adding the new skill as a `skills/escalating-to-workflows/SKILL.md` file with
  valid frontmatter (auto-discovered; no manifest edit — see Part E).
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
should cross-reference the new skill. This A2 rung replacement covers the
**BLOCKED** case specifically; the broader #1 trigger set also names
**DONE_WITH_CONCERNS** and **can't-decide**, but those are *not* BLOCKED returns —
they are additional empirical entry points wired at the #1 leaf itself (Part C),
not inside this SDD BLOCKED-handling rung. The two edit locations are distinct:
do not stuff DONE_WITH_CONCERNS / can't-decide handling into this rung.

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
  - Note: in the actual `burndown-reviews` SKILL.md the line-~43 voice-override
    paragraph is a combined paragraph that *also* establishes loop structure and
    references the spec pseudocode letters. That non-fixer loop-structure content
    must be **preserved** — remove only the fixer-override clause, not the whole
    paragraph.
  - Step F (line ~60) currently reads `model=fixer_model_for_stage` "(the current
    value, after any voice override)". Clean up that parenthetical so it just
    references the fixed `opus` value; do not leave the orphaned "after any voice
    override" reference.
  - Step D contains a separate inline clause: "(D) Pause if any escalated
    disagreements remain — re-check the fixer-model voice override at this pause."
    This is its own sentence, outside the line-~43 paragraph. Remove **only** the
    "re-check the fixer-model voice override at this pause" clause; the surrounding
    step-D disagreement-pause logic must be **preserved**. (Without this target the
    fixer-model override would survive in step D even after the line-~43 paragraph
    and step F are cleaned up.)
- Delete the "Override the fixer model" bullet under "Voice tunables".
- Update the actual edit targets that describe `fixer_model` as "overridable by
  user voice" to state it is always Opus: the `burndown-reviews` **"Inputs"**
  list entry for `fixer_model`, and the `burndown-fixer` agent description. There
  is no fixer-model field in the `burndown-reviews` frontmatter (name +
  description only), so do **not** edit the frontmatter, and do not touch the
  reviewer-pair model frontmatter (the A4 carve-out). **Retain** the `fixer_model`
  input (callers already pass `fixer_model=opus`); no code path may set it to
  anything other than Opus. To be explicit about intent: `fixer_model` is kept as a
  fixed symbolic constant `opus` purely for call-site traceability and minimal diff
  — callers and readers must **not** interpret it as a tunable parameter. (This does
  not reopen the round-1 retain decision; it only makes that decision's intent
  explicit.)

### A4. Reviewer carve-outs (explicitly preserved)

The Sonnet carve-out covers **two** review surfaces, both justified by the same
cross-*model* review-diversity rationale:

(a) **The burndown reviewer pair** (step A and the round-8 inventory pass)
**keeps `model="opus"` + `model="sonnet"`.** State this carve-out explicitly in
the burndown-reviews skill so a future reader does not "consistency-fix" it to
all-Opus: the cross-*model* diversity is the reason the pair exists. The
`burndown-reviewer` agent description's "Opus + Sonnet" framing is retained.

(b) **The escalated multi-model review panels in the #2/#3 leaf wirings**
(Part C) **keep Opus + Sonnet.** These are review leaves, so cross-model
diversity is valuable for exactly the same reason as the reviewer pair. State
this carve-out explicitly so the Part C panels are not "consistency-fixed" to
all-Opus either.

Both carve-outs apply specifically to *review* work; no other site introduces a
non-Opus model.

## Part B — New skill: `escalating-to-workflows`

A new skill at `skills/escalating-to-workflows/SKILL.md`. It is a *reference /
process* skill invoked by other skills (and usable directly), not a primary
user-facing entry point. It holds the pattern so no leaf site duplicates it.

### B1. The three-gate decision rule

This rule is **judgment guidance, subordinate to the B2 empirical trigger** —
B2 is the primary operational mechanism, and these gates only structure the
up-front-escalation judgment call. With that precedence stated up front: a leaf
is escalated from single-agent to a dynamic Workflow **only if all three gates
pass:**

1. **ELIGIBLE** — the leaf is self-contained with *no human gate inside it*, and
   a Workflow can be schema-constrained to return an artifact *shape-compatible*
   with what the single agent returned (so the consuming composition node is
   unchanged).
2. **HARD** — it exhibits irreducible complexity (dense *interacting*
   constraints, not mere line count — e.g. ≥3 requirements that constrain each
   other) **OR** a wide consequential solution space **OR** an unknown-size
   discovery search — **AND** there is no cheap deterministic oracle
   (test/compile/typecheck) that already proves correctness (e.g. no passing
   test/typecheck oracle exists for the leaf).
3. **WORTH IT** — a wrong answer has high blast radius or low reversibility, OR
   the leaf is on the critical path, so the expected cost of a defect exceeds the
   Workflow's token + latency premium (roughly 5–20× a single shot).

**Default is single-agent.** Escalation is the exception, never the norm.

The B2 **empirical trigger is the primary operational mechanism** for deciding to
escalate. These three gates are judgment guidance / tie-breakers applied when
*considering up-front escalation* — they are not a precise checklist, and the
parenthetical proxies above are cheap observable hints, not a rigid rubric.

### B2. The empirical trigger (preferred)

Predicting complexity up front is unreliable. The preferred trigger is
*empirical*: dispatch the leaf single-agent first (the cheap common path), and
escalate the **same** leaf to a Workflow only on a demonstrated-difficulty
return. What "demonstrated difficulty" means is leaf-type-aware, matching the two
families wired in Part C:

- **Implementer leaf (Family I, e.g. #1)** — a `BLOCKED` return, a
  failed-its-own-tests result after N attempts, or an explicit "I see multiple
  viable approaches and can't decide."
- **Fixer leaf (Family I, e.g. #6, #7)** — the leaf's existing retry oracle is
  exhausted: retry-once spent / can't-find-root-cause after the suite still fails.
- **Reviewer leaf (Family II, e.g. #2, #3, #5)** — a reviewer-emitted
  low-confidence / can't-reconcile signal. Reviewers emit no pass/fail self-test
  and no `BLOCKED` return, so they have no empirical oracle of the implementer
  kind; Family II review leaves are therefore **primarily discretionary-gated**
  (the up-front complexity path of B1/B5) rather than empirically gated, with the
  reviewer's own low-confidence signal as the only empirical fallback.

This reserves the premium for leaves that prove they need it.

**N is not a new global constant.** Each call site delegates to its own existing
retry semantics; where a site has no retry counter, the default is "after the
first failed self-test." Concretely, the burndown fixer's retry-once wording (the
#6 row of Part C) governs N at that site: the fixer's existing retry-once is the
N there, and escalation is considered after that retry is exhausted — no separate
counter is introduced.

Up-front escalation (skipping the single-agent attempt) is permitted **only when
at least two signals from the B5 HARD subset specifically are present
simultaneously before dispatch** (the HARD-gate signals enumerated in B5 —
interacting-constraint complexity, wide solution space, unknown-size enumeration —
not the WORTH-IT signals and not the empirical `BLOCKED` trigger; any two of these
three present simultaneously suffice, no specific combination is required);
otherwise use
the empirical path. This pins the up-front bar to a testable condition. (This
complements B1, which is demoted to judgment guidance:
B1 supplies the *kinds* of signal, and this clause sets the concrete count
required to skip the single-agent attempt.)

### B3. Workflow-shape templates (match shape to reason)

- **Interacting-constraint complexity** → `research → implement →
  adversarial-verify` pipeline.
- **Wide consequential solution space** → `parallel()` competing implementers →
  judge panel → synthesize.
- **Unknown-size discovery search** → loop-until-dry (keep dispatching until a
  pass surfaces nothing new).

The three shapes above are keyed to an *up-front* HARD complexity type. When the
escalation is purely **empirical** (Family I — a `BLOCKED` / failed-test return
with no identified complexity type), default to the `research → implement →
adversarial-verify` pipeline (the #1 flagship pattern) unless the blocking signal
points to a specific different root cause — e.g. an explicit "many viable
approaches" signal selects the `parallel()` competing-implementers → judge panel
shape instead.

The internal inter-stage contracts of each shape (what one stage emits and the
next consumes) are the orchestrator's to define when authoring the workflow at
runtime. The only **contractual** output is the final stage's return shape,
governed by B4 (the shaping agent). Do not specify full per-stage schemas here.

### B4. Return-shape contract rule

The composition node consuming the leaf is intentionally untouched, so the
Workflow's final stage **must be a shaping agent** that emits *exactly* the
return contract the single agent produced (status enum, severity-categorized
verdict, summary fields — whatever the call site expects). Richer internal
reasoning is fine; the emitted contract must be a drop-in. A
richer-but-incompatible output is a regression, not an upgrade.

### B5. Escalate-signals and anti-signals

Include the full signal lists as guidance (condensed):

- **Escalate when** — split by which B1 gate each signal serves:
  - *HARD-gate signals* (the irreducible-complexity bar): irreducible
    interacting-constraint complexity; wide + consequential solution space;
    unknown-size enumeration.
  - *WORTH-IT-gate signals* (the cost-of-defect bar): adversarial cross-check
    materially reduces defect risk (security, auth, money/quota, migrations,
    cache-invalidation, silent-corruption modes); high blast radius + low
    reversibility; on the critical path.
  - *Empirical trigger* (not a HARD signal): the leaf returned empirically
    `BLOCKED` (or its leaf-type equivalent per B2). This belongs to the B2
    empirical path, not the up-front HARD subset.
- **Stay single-agent when:** large-but-mechanical / low-entropy; a cheap
  deterministic oracle already proves correctness; low blast radius +
  reversible; purely sequential with no branch points; latency-critical
  interactive path; contains an unavoidable human gate; return shape cannot be
  made compatible.

### B6. Opt-in / invocation note

Native Workflows require explicit user opt-in. Per current Workflow tool
behavior, a skill whose instructions tell the agent to use a Workflow counts as
opt-in — verify this still holds at implementation time — so a leaf site
escalating per this skill is legitimate. The skill should state this so an
implementer does not add a redundant "ask the user first" gate. **Fallback:** if
skill-instruction opt-in is no longer sufficient under the Workflow tool's
then-current rules, the implementer adds a one-time user confirmation at the first
escalation in a session (not per-escalation) and documents that behavior in the
skill.

## Part C — Wiring the seven leaf sites

Each wiring adds an escalation *option behind a gate*; single-agent remains the
default path. The gates come in two families, keyed to the kind of leaf:

- **Family I — empirical / demonstrated-difficulty** (work-producing leaves that
  have a self-test or retry oracle). The **implementer (#1)** escalates on a
  `BLOCKED` / failed-its-own-tests / explicit can't-decide return. The **fixers
  (#6 burndown fixer, #7 per-domain fixer)** escalate when their existing retry
  oracle is exhausted — retry-once spent / can't-find-root-cause after the suite
  still fails. These leaves emit a pass/fail self-test or a retry signal, so the
  trigger is the leaf's own demonstrated difficulty.
- **Family II — discretionary review-gated** (review leaves that emit a VERDICT,
  not a pass/fail self-test). The **code-reviewer (#2)**, **final reviewer (#3)**,
  **code-quality reviewer (#4)**, and **spec-compliance reviewer (#5)** escalate
  either on a high-blast-radius / large diff (the orchestrator's up-front
  complexity judgment) **OR** on a reviewer-emitted low-confidence / can't-reconcile
  signal. Review leaves do **not** emit the implementer-style `BLOCKED` return, so
  that trigger does not apply to them.

In both families single-agent is the default path, and escalate-to-workflow
remains *one option* — never mandatory. Each wiring points at
`escalating-to-workflows` rather than restating the criteria.

| # | Leaf | Skill | Wiring |
|---|------|-------|--------|
| 1 | Implementer subagent | SDD | **Flagship.** BLOCKED-escalation: single first; on BLOCKED / DONE_WITH_CONCERNS / can't-decide, re-dispatch the *same* task as `research → implement → adversarial-verify` (TDD inner loop). Final shaping agent re-emits the DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT status contract. The Part-A2 BLOCKED rung's replacement covers the **BLOCKED** trigger specifically; the **DONE_WITH_CONCERNS** and **can't-decide** triggers are ADDITIONAL empirical entry points wired here at the #1 leaf itself — not inside the SDD BLOCKED-handling rung — so the two edit locations are distinct. |
| 2 | code-reviewer subagent | requesting-code-review | **Family II** (discretionary review-gated): escalate on a high-blast-radius / large diff (orchestrator complexity judgment) OR a reviewer-emitted low-confidence / can't-reconcile signal — not a `BLOCKED` return. Escalate to `parallel()` multi-model reviewers (Opus + Sonnet — deliberate carve-out, see A4) over the same BASE..HEAD range → judge/reconcile → one merged severity-categorized verdict matching the single-agent shape. |
| 3 | Final code reviewer | SDD | **Family II** (discretionary review-gated): escalate on a high-blast-radius / large whole-branch diff (orchestrator complexity judgment) OR a reviewer-emitted low-confidence / can't-reconcile signal — not a `BLOCKED` return. Panel (Opus + Sonnet — deliberate carve-out, see A4) + loop-until-dry enumeration sweep over the whole-branch diff → judge → one consolidated Strengths / Issues / Assessment report. Highest blast-radius review point. |
| 4 | Code-quality reviewer (per task) | SDD | **Mostly inherited from #2** — it reuses the `code-reviewer.md` template. Add only a short pointer note. **Family II** (discretionary review-gated, same as #2): gated on a high-blast-radius / large diff (orchestrator complexity judgment) OR a reviewer-emitted low-confidence / can't-reconcile signal — **not** a `BLOCKED` return (reviewers do not emit `BLOCKED`), and not default-on. |
| 5 | Spec-compliance reviewer | SDD | **Family II** (discretionary review-gated): short pointer gated on a high-blast-radius / hard spec (orchestrator complexity judgment) OR a reviewer-emitted low-confidence / can't-reconcile signal — not a `BLOCKED` return. On escalation: `research (re-read spec + code) → adversarial verify enumerating each requirement → emit compliant/issues list`. |
| 6 | Fixer (step F) | burndown-reviews | **Family I** (empirical / retry-oracle): escalate when the fixer's existing retry oracle is exhausted (retry-once spent and the suite still fails) — not a discretionary up-front gate. **Impl-stage substantive fixes only**: `research → apply → self-verify-against-findings` → emit the exact deferred-IDs / created / deleted / summary contract. Applies B5 anti-signal "large-but-mechanical / low-entropy" — mechanical typo/format findings stay single-agent; only substantive impl-stage fixes escalate. Retry-once + crash-abort semantics preserved. |
| 7 | Per-domain fixer | dispatching-parallel-agents | BLOCKED-gated pointer on the *individual leaf* (not the fan-out, which stays a composition): single first; on can't-find-root-cause / repeated failures, re-dispatch the same domain as `systematic-debug → fix → verify`, emitting the same root-cause + changes summary. Unlike #6, this fixer has no dedicated retry counter, so it uses B2's "no retry counter → after the first failed self-test" default (the suite still failing after the single-agent fix attempt) — mirroring how #6's retry-once pins N at that site. |

**Shared-template note for #2/#4:** the SDD code-quality reviewer dispatches the
`spandapowers:code-reviewer` subagent type using the shared
`requesting-code-review/code-reviewer.md` template (wrapped by the local
`code-quality-reviewer-prompt.md`, which adds extra checks). Because #4 is built
on that shared template, upgrading #2 at the template level delivers most of #4
automatically. Concretely, the escalation pointer is added to
`requesting-code-review/code-reviewer.md` (the shared template invoked via the
`spandapowers:code-reviewer` agent), so BOTH `requesting-code-review` (#2) and
SDD's code-quality reviewer (#4) inherit it with NO edit to
`code-quality-reviewer-prompt.md` (the local wrapper). #4's edit is then just a
gate-and-pointer.

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

- **No stray cheaper-model references:** scope this check to the files this work
  actually edits — the `subagent-driven-development`, `burndown-reviews`, and
  `requesting-code-review` skills, the `burndown-reviewer` / `burndown-fixer`
  agents, and the new `escalating-to-workflows` skill. Within that scope, the only
  surviving Sonnet / non-Opus references are the deliberate review carve-outs
  (Part A4): (a) the burndown reviewer pair and (b) the escalated multi-model
  review panels in the #2/#3 leaf wirings. Grep that file set to confirm; any
  NEW or LEFTOVER cheaper-model reference there (outside the carve-outs) is a bug.
  Pre-existing, out-of-scope model-tier references in unrelated skills — e.g. the
  Sonnet/Haiku/Opus model-tier testing guidance in
  `skills/writing-skills/anthropic-best-practices.md` — are **out of scope** and
  must not be edited by this work.
- **Skill registration:** creating `skills/escalating-to-workflows/SKILL.md` with
  valid frontmatter (a `name` and `description`) is sufficient for discovery —
  skills are auto-discovered from the `skills/` directory, so no manifest edit is
  needed. `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json` must
  **NOT** be touched: they describe the single `spandapowers` plugin (source
  `./`), not individual skills, and neither enumerates skills.
- **Skill-triggering tests:** `escalating-to-workflows` is a reference skill
  invoked by other skills and is intentionally **excluded** from the
  skill-triggering suite (`tests/skill-triggering/run-all.sh`), which covers only
  user-facing entry points. That suite uses a hardcoded, curated `SKILLS=()` array
  of user-facing skills (`burndown-reviews`, `systematic-debugging`,
  `test-driven-development`, `writing-plans`, `dispatching-parallel-agents`,
  `executing-plans`, `requesting-code-review`) — it does not enumerate skills.
  Add no prompt file and no `SKILLS`-array entry for the new skill.
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

None blocking.
