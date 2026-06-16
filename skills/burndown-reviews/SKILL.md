---
name: burndown-reviews
description: "Multi-model subagent review loop run at superpowers checkpoints. Dispatched by brainstorming, writing-plans, and subagent-driven-development BEFORE their user-review gate. Drives Opus + Sonnet reviewers concurrently, applies findings round-by-round via a fixer subagent, escalates only when the orchestrator disagrees with a reviewer."
---

# Burndown Reviews

## Overview

Run a bounded multi-model subagent review loop on an artifact (spec, plan, or working tree). Burn down findings round by round until the artifact is clean or the round cap is hit. Pause to escalate only when the orchestrator (you, main Claude) disagrees with a reviewer's finding — solo findings are normal output.

**Announce at start:** "Running burndown-reviews on the {stage} artifact."

## Inputs (provided by the parent skill at invocation)

- `artifact_path` — file (or working-tree scope) under review
- `predecessor` — structured value, shape varies by stage:
  - `spec` stage: path to `<artifact_basename>.context.md`
  - `plan` stage: path to the spec
  - `impl` stage: object `{ plan_path, diff_base, diff_paths }` populated by SDD
- `fixer_model` — always `opus` for all stages. Retained as a fixed symbolic constant for call-site traceability and minimal diff; **not** a tunable parameter — no code path may set it to anything other than `opus`.
- `stage` — `spec` | `plan` | `impl`

## Spec

Authoritative behavior is defined in `docs/superpowers/specs/2026-05-04-burndown-reviews-design.md`. This skill file is the operational checklist; consult the spec for the why and the edge cases.

## Loop execution

Initialize once before the loop:

```
deferred_findings = []
prev_deferred_id_set = None
prev_artifact_hash = None
abort_error = None
fixer_model_for_stage = opus   # fixed for all stages; not tunable
```

For each round 1 through 7:

The loop steps below are labeled to match the spec pseudocode's letters (A through F-bis), with the same operations and ordering.

1. **(A) Dispatch reviewers concurrently** — issue both Task calls in a single message with the `burndown-reviewer` agent, one with `model="opus"`, one with `model="sonnet"` (these exact strings — the Task tool's `model` parameter overrides the agent's `model: inherit` frontmatter). Pass `stage`, `artifact_path`, and the predecessor context. Both run in parallel. The orchestrator stamps the returned findings post-hoc as `opus-r{round}-{n}` / `sonnet-r{round}-{n}` and concatenates them with the prior round's `deferred_findings` (which retain their older IDs) into `all_findings`. (**Deliberate carve-out — do not "consistency-fix":** the `opus`+`sonnet` pairing is intentional cross-*model* review diversity, the entire reason the pair exists. This is the only *always-on* reviewer-pair Sonnet usage and it stays (the #2/#3 escalated review panels are a separate, gated carve-out).)
2. **(B) Judge each finding** — for each entry in `all_findings`, choose one of three verdicts:
   - **Accept** — finding is real and the suggested fix is sound. Add to `fix_list`.
   - **Override** (confident) — you can verify the reviewer is wrong against the spec, the artifact, or the locked decisions. Drop silently; do not escalate. The user's time is the scarce resource you are protecting. **An Override verdict on a deferred finding retires its ID** (per spec § "Override of a previously-deferred finding") — it does not appear in subsequent rounds.
   - **Escalate** (uncertain) — you suspect the reviewer is wrong but cannot fully verify, or the call genuinely depends on user judgment. Add to `disagreements`.

   **High-escalation-rate edge case (fires here, after judgment is complete):** if `len(disagreements)` is unusual (round 1: more than half of `len(all_findings)`; round 2+: significantly above the run's prior-round cadence), pause and offer the user three concrete options before continuing to step C: (a) skip remaining escalations this round (treat as confident overrides), (b) abort the loop so the user can edit the reviewer agent definition and restart, or (c) keep going as-is.
3. **(C) Merge near-duplicates** — collapse `fix_list` and `disagreements` **independently** (never across the two lists). Same merge rules apply to both:
   - **Location match** — same full heading chain (prose) or overlapping line range (code; merged location = union, smallest start to largest end).
   - **Severity adjacency** — H↔M mergeable, M↔L mergeable, H↔L NOT mergeable (non-transitive). Merged severity = max of the two.
   - **ID survival** — when a deferred finding (carrying older ID) merges with a fresh finding, retain the **older** deferred ID for traceability. When two fresh findings of the same round merge, pick either.
   - **Fix-list match** uses `suggested_fix` similarity (same intervention?). **Disagreement-list match** uses `claim` similarity (the user is choosing what to do, so contradictory fix text is informative).
   - **Conflicting fixes at same location in fix_list:** the orchestrator must NEVER pass two contradictory `suggested_fix` strings to the fixer. Pick one and override or escalate the other; or, if the fixes are genuinely complementary, author a synthesized fix instruction in your own words and **log it in the round summary** so the rewrite is auditable. Prefer pick-one over rewriting.
4. **(D) Pause if any escalated disagreements remain** — surface disagreements to the user in plain language, batched per round. Use the Disagreement UX from the spec (state finding, explain disagreement, offer recommendation, listen, restate). Block until the user finishes resolving every escalated item. Add user-resolved "keep" findings to `fix_list` (with the user's text replacing the reviewer's `suggested_fix` if they wrote one).
5. **(E) Early-clean check** — if `fix_list` is empty, return "clean" and emit the trajectory report. (User-skipped escalations and orchestrator overrides both count as cleared.)
6. **(F) Dispatch the fixer subagent** — single Task call with the `burndown-fixer` agent and `model=fixer_model_for_stage` (always `opus`). Pass `artifact_path`, the reconciled `fix_list`, and `stage` (plus `diff_paths` and `diff_base` for impl). Verify content changed via sha256 hash before/after, with these legitimacy rules:
   - **Hash domain:** for prose artifacts (spec, plan), hash the artifact file's full bytes. For impl stage, hash the concatenated full contents of files in `diff_paths` (sorted by path), treating any deleted file's contents as empty bytes — so deletions register as a real content change rather than a hash collision.
   - **Unchanged content + non-empty deferred list = legitimate.** The fixer determined it could apply none of the findings cleanly. Do NOT retry; advance to round N+1 with the deferred list carried forward.
   - **Unchanged content + empty deferred list + non-empty fix_list = failure.** Retry once. If still unchanged, set `abort_error` and break (fatal abort).
   - **New-files exemption:** if `fixer_result.created_paths` is non-empty, skip the unchanged-content failure check for this round entirely — the new-file report is itself authoritative evidence the fixer did work. Extend in-loop `diff_paths` with the new paths.
   - **Reviewer/fixer crash retry:** any reviewer or fixer crash retries once within the same round (does not consume a round slot). Two consecutive crashes → fatal abort.
   - **Conflicting fixes never reach the fixer:** before this dispatch, the merge step (C) must have ensured that two contradictory `suggested_fix` strings at the same location were resolved (orchestrator picks one, escalates the other, or authors a logged rewrite). The fixer must never receive contradictory instructions for the same location.
   On fatal abort, set `abort_error = fixer_result.error` and break out of the loop — round 8 still runs (the user gets the abort error alongside a current-state finding list).
   - **Complex-fix escalation (Family I):** the fixer is a Family I leaf — escalate it to a dynamic Workflow only when its retry oracle is exhausted (retry-once spent and the artifact/suite still wrong), and only for **substantive impl-stage fixes**. Mechanical typo/format findings stay single-agent (the "large-but-mechanical / low-entropy" anti-signal — see spandapowers:escalating-to-workflows). On escalation: `research → apply → self-verify-against-findings` → emit the exact `deferred` / `created_paths` / `deleted_paths` / summary contract. Retry-once + crash-abort semantics are preserved. See spandapowers:escalating-to-workflows.
7. **(F-bis) Update `deferred_findings` and check non-progress** — split into two atomic sub-steps:
   - **(F-bis-1)** Update `deferred_findings = fixer_result.deferred` (replaces, not appends — earlier-round deferrals were already re-judged in step B). Update in-loop `diff_paths` from `fixer_result.created_paths` (extend) and `fixer_result.deleted_paths` (remove).
   - **(F-bis-2)** Compute `current_artifact_hash = hash_of(artifact)` and `current_deferred_id_set = {f.id for f in deferred_findings}`. If `current_artifact_hash == prev_artifact_hash` AND `current_deferred_id_set == prev_deferred_id_set` AND `current_deferred_id_set` is non-empty → break out of the loop early (non-progress short-circuit; round 8 still runs). Otherwise, advance the trackers: `prev_artifact_hash = current_artifact_hash` and `prev_deferred_id_set = current_deferred_id_set`. Without this advance, the trackers stay frozen at their initial `None` values and the short-circuit can never fire correctly.

After the loop (round 8 — inventory pass):

- Dispatch both reviewers concurrently with the same inputs as in step A. Stamp findings with the **actual round number** the loop terminated at: typically `opus-r8-{n}` / `sonnet-r8-{n}` for the initial inventory; `opus-r{N}-{n}` / `sonnet-r{N}-{n}` for a post-extension inventory (e.g., `r18` after 10 extension rounds concluding at round 18). Do NOT hardcode `r8` for post-extension inventory passes.
- Merge `final_opus + final_sonnet + deferred_findings` using the in-loop merge rules. Carried-deferred entries keep older IDs. **The `[deferred since r{N}]` annotation is added at the residual-emission step (immediately before user surface), based on the merged entry's surviving ID** — if a deferred ID survived the merge, annotate; otherwise don't.
- Termination logic — three cases:
  - `residual` empty AND `abort_error` is None → return "clean".
  - `abort_error` is not None (regardless of residual size) → surface the abort error AND the residual list together; mark as hard_escalate-with-abort.
  - `residual` non-empty AND `abort_error` is None → surface the residual with: "**N rounds didn't converge**. Here's what's still flagged. Accept as-is, run more rounds, or fix manually?" — where `N` is the actual last round number (8 for the initial inventory, or the extension round number for post-extension inventories). Do NOT hardcode "7 rounds" — the message must match the run's actual round count.

**High-escalation-rate edge case (within the loop):** if the orchestrator finds itself escalating an unusually large fraction of findings in a single round, that's a signal of miscalibration. For round 1, "unusual" = more than half of all findings escalated. For round 2+, "unusual" = significantly above the run's prior-round cadence. When triggered, the orchestrator pauses and offers the user three concrete options: (a) skip remaining escalations this round (treat as confident overrides), (b) abort the loop so the user can edit the reviewer agent definition and restart, or (c) keep going as-is.

After every termination (clean, hard escalate, or fatal abort): emit the trajectory report (see "Trajectory report" below).

## Voice tunables

Listen for these intents:

- **"Run more rounds"** — after a hard-escalate. The user specifies a number; restart the inner loop fresh (`deferred_findings = []`, `abort_error = None`, trackers reset) for that many rounds, with sequential numbering (round 9, 10, ...). After exhaustion, run another inventory pass with the actual round number.

The "skip burndown" intent is handled by the parent skill, not here — by the time this skill is invoked, the parent has already decided.

## Trajectory report

On every termination, emit a markdown table to the user with these columns:

- Round | Findings | H | M | L | nit | Applied | Override | Escalated (kept/skipped) | Deferred

Plus a Σ totals row. Round-8 inventory rows show Findings + severity breakdown only (the judge/fix columns are blank because round 8 doesn't judge or fix). See the spec for an example.
