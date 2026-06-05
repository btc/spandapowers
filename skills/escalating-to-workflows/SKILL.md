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

Skipping the single-agent attempt is permitted **only when the HARD gate below is met by at least two of its three signals present simultaneously** before dispatch (any two of the three HARD signals suffice; no specific combination required). Otherwise use the empirical path.

The three-gate rule structures that judgment call. Escalate up-front only if **all three gates** (ELIGIBLE, HARD, WORTH IT) pass:

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
