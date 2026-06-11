# Burndown Reviews Manual Verification

End-to-end verification runs real subagent dispatches and is expensive — not appropriate for CI. Run on demand when changes touch the loop logic.

## Setup

Fixtures live under `tests/burndown-reviews/fixtures/`.

## Procedure 1: Deliberately-flawed fixture

1. Copy `fixtures/flawed-spec.md` to a scratch location: `cp fixtures/flawed-spec.md /tmp/flawed.md`.
2. Create a minimal context file: `echo "Test fixture for manual verification." > /tmp/flawed.context.md`.
3. Invoke a fresh Claude session with superpowers loaded.
4. Prompt: `Run the burndown-reviews skill on /tmp/flawed.md, with stage=spec, predecessor=/tmp/flawed.context.md, fixer_model=fable.`

Expected behavior:
- Round 1 finds H or M findings (architectural contradiction, vague motivation, duplicated components, etc.).
- Subsequent rounds: finding count decreases.
- Loop returns "clean" before round 7, OR hits round 8 inventory with **fewer than half the round-1 finding count** in the residual.
- Final trajectory report is emitted with at least one round showing >0 findings, the H/M/L/nit columns populated, and a non-empty Σ totals row.

If the loop fails to converge (round 8 residual ≥ half of round 1's finding count) or the trajectory report is missing, that's a regression.

## Procedure 2: Clean fixture

Same setup with `fixtures/clean-spec.md`.

Expected behavior:
- Round 1 returns "No findings" from both reviewers.
- Loop returns "clean" immediately.
- Trajectory report shows a single row with 0 findings and a Σ totals row.

If round 1 produces non-trivial findings on the clean fixture, the reviewer rubric or per-stage focus may be too strict.

## Procedure 3: Disagreement escalation

Create `/tmp/escalation-test-spec.md` with a deliberate orchestrator-vs-reviewer disagreement trigger:

- A section that is locked-in per the context file (e.g., `/tmp/escalation-test.context.md` says "DECISION: use a single-table schema, denormalize aggressively") but the spec body invites the reviewer to flag it as a concern (e.g., "Architecture: single-table schema with deliberate denormalization — this is a known design trade-off chosen for read latency").

Run the burndown procedure as in Procedure 1. Expected behavior:
- A reviewer will probably flag the denormalization as an anti-pattern.
- The orchestrator should recognize the context file's lock-in, **override** the finding confidently (no escalation), and continue.

If the orchestrator escalates this to the user instead, that's a regression: the orchestrator-confidence rule isn't being applied. If the orchestrator silently applies the reviewer's fix (rewriting the schema), that's also a regression: the locked decision wasn't preserved.
