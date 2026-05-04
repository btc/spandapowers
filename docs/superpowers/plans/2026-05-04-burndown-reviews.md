# Burndown Reviews Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an automated multi-model subagent review loop (Opus + Sonnet, up to 7 rounds) that runs at the spec, plan, and impl checkpoints of the Superpowers workflow before the existing user-review gate.

**Architecture:** A new shared skill `burndown-reviews` drives the loop; two new agent definitions (`burndown-reviewer`, `burndown-fixer`) are dispatched with model overrides per call; the three existing parent skills (`brainstorming`, `writing-plans`, `subagent-driven-development`) gain a small invocation step inserted before their existing user-review step. Reconcile and orchestration are prose-driven (executed by the main Claude orchestrator) — no callable functions are introduced. Tests are bash-driven, matching the existing `tests/` conventions.

**Tech Stack:** Markdown skills + agents (no code), bash test harness, semver build-metadata for fork versioning.

**Spec:** `docs/superpowers/specs/2026-05-04-burndown-reviews-design.md`

**Branch:** `burndown-reviews` on `btc/superpowers` fork (already created).

**Test convention adaptation:** The spec's "orchestrator-simulation tests" idea (open question 2) is adapted here to the codebase's actual test framework: bash scripts that drive `claude -p` against fixture inputs. The orchestrator-simulation test target would require a mock-subagent framework that does not exist in this codebase; building one is out of scope. Instead: one skill-triggering test (cheap, automated) + manual-verification procedures for end-to-end runs (gated, runnable on-demand).

---

## File Map

**Create:**
- `skills/burndown-reviews/SKILL.md` — orchestration loop, prose-driven
- `agents/burndown-reviewer.md` — single agent file; orchestrator picks model at dispatch
- `agents/burndown-fixer.md` — single agent file; orchestrator picks model at dispatch
- `tests/burndown-reviews/run-triggering-test.sh` — skill-triggering test
- `tests/burndown-reviews/triggering-prompt.txt` — naive prompt that should activate burndown-reviews
- `tests/burndown-reviews/MANUAL-VERIFICATION.md` — fixture-based manual verification procedure
- `tests/burndown-reviews/fixtures/flawed-spec.md` — deliberately-flawed spec for convergence test
- `tests/burndown-reviews/fixtures/clean-spec.md` — clean spec, should converge in 1 round

**Modify:**
- `skills/brainstorming/SKILL.md` — add skip detection at start; insert burndown step between current steps 7 and 8; write context file as part of new burndown step
- `skills/writing-plans/SKILL.md` — add skip detection at start; insert burndown invocation immediately before the Execution Handoff section
- `skills/subagent-driven-development/SKILL.md` — add skip detection at start; capture `diff_base` at first step before any Task call; insert burndown invocation immediately before the final hand-off to `finishing-a-development-branch`
- `package.json` — bump version to `5.0.7+btc.1` (semver build metadata; does not affect precedence)
- `RELEASE-NOTES.md` — add `5.0.7+btc.1` entry describing the fork divergence

**Marketplace repo (separate, optional final chunk):**
- Create new GitHub repo `btc/claude-plugins` (public)
- Local clone at `~/Projects/src/claude-plugins`
- File: `.claude-plugin/marketplace.json` pointing the `superpowers` plugin at `btc/superpowers`

---

## Chunk 1: Subagent Definitions

### Task 1: Create the burndown-reviewer agent

**Files:**
- Create: `agents/burndown-reviewer.md`

- [ ] **Step 1: Create the agent file with frontmatter and role framing**

```markdown
---
name: burndown-reviewer
description: |
  Critical reviewer of a Superpowers-driven artifact (spec, plan, or impl). Dispatched concurrently as both Opus and Sonnet by the burndown-reviews skill; the orchestrator picks the model at dispatch time via the `model` parameter. Reads the artifact and the predecessor context, returns a list of structured findings. Does not edit any file.
model: inherit
---

You are a critical reviewer of a `{stage}` artifact in a Superpowers-driven workflow. Your only job is to review — DO NOT edit any file.

The orchestrator dispatches you with the following inputs in the prompt:

- `stage`: one of `spec` | `plan` | `impl`
- Path to the artifact under review
- Predecessor context — shape varies by stage:
  - `spec` stage: a single path to a context file `<artifact_basename>.context.md`
  - `plan` stage: a single path to the spec the plan was derived from
  - `impl` stage: an object `{ plan_path, diff_base, diff_paths }` — read the diff between `diff_base` and `HEAD` restricted to `diff_paths`

Your job: find substantive issues that would prevent the artifact from doing its job. Be direct. Don't pad. Don't restate the artifact.

## Severity rubric

- **H** (high): blocks the artifact from being usable. Spec contradictions, missing critical info, scope drift, code that fails tests or breaks the build.
- **M** (medium): substantive issue to fix before moving on. Unclear requirement, missing error handling, gap in test coverage, ambiguous step.
- **L** (low): improvement, not blocking. Naming, redundant content, minor reorg.
- **nit**: trivial polish. Typos, formatting, word choice.

## Per-stage focus

- **spec**: scope, contradictions, vague or unmeasurable requirements, missing constraints, testability, ambiguity that would let two implementers diverge.
- **plan**: each step's preconditions and postconditions, ordering and dependencies, scope match against the spec, over-engineering, missing decision points.
- **impl**: code matches plan, tests exist and pass, no regressions, follows project conventions, no scope creep, diff is minimal for what was asked.

## Output format

Emit one entry per finding. No preamble, no summary, no commentary outside findings. Use sequential numeric IDs (`1`, `2`, `3`, ...) — the orchestrator namespaces them post-hoc with reviewer name and round number.

```
## Finding {n}
- severity: H | M | L | nit
- location: <location specifier — see below>
- claim: <1-3 sentences — what's wrong>
- suggested_fix: <1-3 sentences — what to do>
```

### Location specifier rules

- **Prose artifacts (spec, plan):** `<path> § "<H2>" / "<H3>" / ...` — full heading chain. Examples: `spec.md § "Architecture" / "Failure modes"`, `spec.md § "Architecture" / "The loop" ¶3`. Pre-H2 content uses `<path> § (preamble)`. Code blocks within prose use `<path> § "<H2>" / "<H3>" code-block:L<n>`.
- **Code artifacts (impl):** `<path>:L<start>-L<end>` — e.g., `src/loop.ts:L42-58`. Single-line: `src/loop.ts:L42`.
- **Either is acceptable for impl-stage prose docs** (e.g., README updates).

If the artifact is clean, output exactly: `No findings.`
```

- [ ] **Step 2: Verify the file is well-formed YAML frontmatter + markdown body**

Run: `head -5 agents/burndown-reviewer.md`
Expected: starts with `---`, has `name: burndown-reviewer`, has `description:`, has `model: inherit`, then closes with `---`.

- [ ] **Step 3: Commit**

```bash
git add agents/burndown-reviewer.md
git commit -m "Add burndown-reviewer agent definition"
```

### Task 2: Create the burndown-fixer agent

**Files:**
- Create: `agents/burndown-fixer.md`

- [ ] **Step 1: Create the agent file with frontmatter and role framing**

```markdown
---
name: burndown-fixer
description: |
  Applies a reconciled finding list to a Superpowers-driven artifact. Dispatched by the burndown-reviews skill; the orchestrator picks the model at dispatch time (sonnet for spec/plan stages; opus for impl stage; overridable by user voice).
model: inherit
---

You are a fixer applying review findings to a `{stage}` artifact in a Superpowers-driven workflow.

The orchestrator dispatches you with the following inputs in the prompt:

- Path to the artifact
- The reconciled finding list (post-disagreement-resolution) — each entry has `id`, `severity`, `location`, `claim`, `suggested_fix`
- `stage`: one of `spec` | `plan` | `impl`
- For `impl` stage only: `diff_paths` (the in-scope file list) and `diff_base` (commit SHA)

## Your job

Address every finding. Preserve unrelated content. Make minimal edits — fix what's flagged, nothing else.

For `impl` stage: do not modify files outside `diff_paths` except by creating new files or deleting in-scope files (both must be reported in your output).

## Output

Return a structured response with these fields:

- The updated artifact, written in place via the Edit/Write tools.
- `deferred`: a list of finding IDs you were unable to apply due to intra-round conflicts (overlapping content with incompatible required edits). Possibly empty.
- `created_paths` (impl stage only): a list of any new file paths you created outside the input `diff_paths`. Possibly empty.
- `deleted_paths` (impl stage only): a list of any file paths you removed. Possibly empty.
- A brief human-readable summary of what you changed (for the orchestrator's logs).

If you cannot apply a finding because two findings demand contradictory edits to overlapping content, apply the higher-severity one and add the other to `deferred`. Never leave the artifact in a broken/partially-edited state.
```

- [ ] **Step 2: Verify the file is well-formed**

Run: `head -5 agents/burndown-fixer.md`
Expected: same frontmatter shape as Task 1.

- [ ] **Step 3: Commit**

```bash
git add agents/burndown-fixer.md
git commit -m "Add burndown-fixer agent definition"
```

---

## Chunk 2: Skill Orchestration

### Task 3: Create the burndown-reviews skill

**Files:**
- Create: `skills/burndown-reviews/SKILL.md`

- [ ] **Step 1: Create the skill file with frontmatter, overview, and inputs**

```markdown
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
- `fixer_model` — `sonnet` for spec & plan; `opus` for impl. Overridable by user voice.
- `stage` — `spec` | `plan` | `impl`

## Spec

Authoritative behavior is defined in `docs/superpowers/specs/2026-05-04-burndown-reviews-design.md`. This skill file is the operational checklist; consult the spec for the why and the edge cases.
```

- [ ] **Step 2: Append the loop execution checklist**

Append to the same file:

```markdown
## Loop execution

Initialize once before the loop:

```
deferred_findings = []
prev_deferred_id_set = None
prev_artifact_hash = None
abort_error = None
fixer_model_for_stage = sonnet if stage in {spec, plan} else opus
   # overridable by user voice; last-write wins (see "Voice tunables")
```

For each round 1 through 7:

1. **A. Dispatch reviewers concurrently** — issue both Task calls in a single message with the `burndown-reviewer` agent, one with `model=opus`, one with `model=sonnet`. Pass `stage`, `artifact_path`, and the predecessor context. Both run in parallel.
2. **B. Stamp finding IDs post-hoc** — namespace each reviewer's sequential IDs as `opus-r{round}-{n}` and `sonnet-r{round}-{n}`. Concatenate Opus output, Sonnet output, and the prior round's `deferred_findings` (which retain their original older IDs) into one `all_findings` list.
3. **C. Judge each finding** — for each entry in `all_findings`, choose one of three verdicts:
   - **Accept** — finding is real and the suggested fix is sound. Add to `fix_list`.
   - **Override** (confident) — you can verify the reviewer is wrong against the spec, the artifact, or the locked decisions. Drop silently; do not escalate. The user's time is the scarce resource you are protecting.
   - **Escalate** (uncertain) — you suspect the reviewer is wrong but cannot fully verify, or the call genuinely depends on user judgment. Add to `disagreements`.
4. **D. Merge near-duplicates** — collapse `fix_list` and `disagreements` independently using the merge rules in the spec (location match, severity adjacency H↔M and M↔L only, ID survival prefers older deferred IDs). For the disagreement list, match on `claim` similarity rather than `suggested_fix` (the user is choosing what to do).
5. **E. Pause if any escalated disagreements remain** — surface them to the user in plain language, batched per round. Use the Disagreement UX from the spec (state finding, explain disagreement, offer recommendation, listen, restate). Block until the user finishes resolving every escalated item. Add user-resolved "keep" findings to `fix_list` (with the user's text replacing the reviewer's `suggested_fix` if they wrote one).
6. **F. Early-clean check** — if `fix_list` is empty, return "clean" and emit the trajectory report. (User-skipped escalations and orchestrator overrides both count as cleared.)
7. **G. Dispatch the fixer subagent** — single Task call with the `burndown-fixer` agent and `model=fixer_model_for_stage`. Pass `artifact_path`, `fix_list`, and `stage` (plus `diff_paths` and `diff_base` for impl). Verify content changed via sha256 hash before/after, applying the legitimacy rules in the spec (unchanged + non-empty deferred = OK; new files reported = OK; otherwise retry once, abort if still failing). On fatal abort, set `abort_error` and break out of the loop — round 8 still runs.
8. **H. Update `deferred_findings`** from `fixer_result.deferred` (replaces, not appends). Update in-loop `diff_paths` from `fixer_result.created_paths` and `fixer_result.deleted_paths` (impl stage). Compute the current artifact hash and deferred-ID set; if both equal the prior round's values and the deferred set is non-empty, break out of the loop early (non-progress short-circuit).

After the loop (round 8 — inventory pass):

- Dispatch both reviewers concurrently with the same inputs as in step A. Stamp findings as `opus-r8-{n}` / `sonnet-r8-{n}` (or actual round number on extension paths).
- Merge `final_opus + final_sonnet + deferred_findings` using the in-loop merge rules. Carried-deferred entries keep older IDs and get a `[deferred since r{N}]` annotation in the user-facing surface.
- If `residual` is empty AND `abort_error` is None: return "clean".
- If `abort_error` is set: surface the abort error alongside the residual.
- Otherwise: surface the residual to the user with: "7 rounds didn't converge. Here's what's still flagged. Accept as-is, run more rounds, or fix manually?"

After every termination (clean, hard escalate, or fatal abort): emit the trajectory report (see "Trajectory report" below).

## Voice tunables

Listen for these intents:

- **"Run more rounds"** — after a hard-escalate. The user specifies a number; restart the inner loop fresh (`deferred_findings = []`, `abort_error = None`, trackers reset) for that many rounds, with sequential numbering (round 9, 10, ...). After exhaustion, run another inventory pass.
- **Override the fixer model** — at the start of round 1, on each disagreement-pause, or during the round-8 hard-escalate exchange. Last-write wins. Update `fixer_model_for_stage` and use it for all subsequent fixer dispatches.

The "skip burndown" intent is handled by the parent skill, not here — by the time this skill is invoked, the parent has already decided.

## Trajectory report

On every termination, emit a markdown table to the user with these columns:

- Round | Findings | H | M | L | nit | Applied | Override | Escalated (kept/skipped) | Deferred

Plus a Σ totals row. Round-8 inventory rows show Findings + severity breakdown only (the judge/fix columns are blank because round 8 doesn't judge or fix). See the spec for an example.
```

- [ ] **Step 3: Verify the file is well-formed**

Run: `head -5 skills/burndown-reviews/SKILL.md && wc -l skills/burndown-reviews/SKILL.md`
Expected: starts with `---`, has `name: burndown-reviews`, `description:`, then `---`. Roughly 100-130 lines total.

- [ ] **Step 4: Commit**

```bash
git add skills/burndown-reviews/SKILL.md
git commit -m "Add burndown-reviews skill"
```

---

## Chunk 3: Parent Skill Integration

### Task 4: Edit brainstorming/SKILL.md

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

The current brainstorming checklist is:
1. Explore project context
2. Offer visual companion
3. Ask clarifying questions
4. Propose 2-3 approaches
5. Present design
6. Write design doc
7. Spec self-review
8. User reviews written spec
9. Transition to implementation

Three changes are needed:
1. Add a skip-burndown detection step at the very top.
2. Insert a new step between current 7 and 8 that writes the predecessor context file and invokes burndown-reviews.
3. Re-check skip intent immediately before invoking burndown-reviews (last-write wins).

- [ ] **Step 1: Read the current SKILL.md to find anchor lines**

Run: `grep -n "^## \|^### " skills/brainstorming/SKILL.md`
Expected: see the section headings. Note the line numbers of "## Checklist" and the numbered checklist items.

- [ ] **Step 2: Add a skip-burndown detection note at the top of the Checklist section**

Use the Edit tool to add (just below the current "## Checklist" heading and intro paragraph):

```markdown
**Burndown skip detection (always step 0):** Before starting any of the steps below, check whether the user has expressed an intent to skip the burndown review for this run (e.g., "skip the burndown for this one"). Treat ambiguous intent ("maybe skip it") as not skipping. If a clear skip intent is detected, set `burndown_skip = true`. If not detected, leave it unset.
```

- [ ] **Step 3: Renumber the checklist to insert the new step between current 7 and 8**

The new checklist items become:
1. Explore project context
2. Offer visual companion
3. Ask clarifying questions
4. Propose 2-3 approaches
5. Present design
6. Write design doc
7. Spec self-review
8. **Burndown review pass (NEW)** — if `burndown_skip` is true (re-check intent here; last-write wins), skip this step. Otherwise: write `<artifact_basename>.context.md` alongside the spec containing a best-effort summary of the user's original request, locked-in design decisions, and explicit non-goals (sections may be empty if not produced during the brainstorm). Then invoke the `burndown-reviews` skill with `stage=spec`, `artifact_path=<spec path>`, `predecessor=<context file path>`, `fixer_model=sonnet`. Wait for the loop to terminate. The loop's trajectory report goes to the user as part of its return.
9. User reviews written spec
10. Transition to implementation

Use Edit to replace the existing 8-step list with this 10-step list. Preserve formatting.

- [ ] **Step 4: Update the Process Flow diagram**

The mermaid/dot diagram in the Process Flow section references the steps. Update it to add a "Burndown review pass" node between "Spec self-review (fix inline)" and "User reviews spec?".

- [ ] **Step 5: Verify the file still parses as well-formed markdown**

Run: `grep -c "^[0-9]\+\. " skills/brainstorming/SKILL.md`
Expected: `10` (10 numbered checklist items).

- [ ] **Step 6: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "brainstorming: insert burndown review pass between spec self-review and user review"
```

### Task 5: Edit writing-plans/SKILL.md

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

Current ending: the "Self-Review" section, then "Execution Handoff" which prompts the user to choose between subagent-driven and inline execution.

Insertion point: between the "Self-Review" section's end and the "Execution Handoff" section's start.

- [ ] **Step 1: Find the anchor**

Run: `grep -n "^## " skills/writing-plans/SKILL.md`
Expected output includes `## Self-Review` and `## Execution Handoff`.

- [ ] **Step 2: Add skip detection at the top**

Use Edit to add after the "## Overview" section's closing paragraph:

```markdown
**Burndown skip detection (always first):** Before starting plan-writing, check whether the user has expressed an intent to skip the burndown review for this run. Treat ambiguous intent as not skipping. Set `burndown_skip` accordingly.
```

- [ ] **Step 3: Insert the burndown invocation between Self-Review and Execution Handoff**

Use Edit to insert a new section between `## Self-Review` and `## Execution Handoff`:

```markdown
## Burndown Review Pass

After the inline self-review passes, and before the Execution Handoff:

If `burndown_skip` is true (re-check intent here; last-write wins): skip this section.

Otherwise: invoke the `burndown-reviews` skill with `stage=plan`, `artifact_path=<plan file path>`, `predecessor=<spec file path>`, `fixer_model=sonnet`. Wait for the loop to terminate. The trajectory report is shown to the user as part of its return.
```

- [ ] **Step 4: Verify the file is well-formed**

Run: `grep -c "^## " skills/writing-plans/SKILL.md`
Expected: count goes up by 1 vs. baseline.

- [ ] **Step 5: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "writing-plans: insert burndown review pass before execution handoff"
```

### Task 6: Edit subagent-driven-development/SKILL.md

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`

Two changes:
1. Capture `diff_base` (current HEAD SHA) and verify clean working tree as the very first step, before any Task call.
2. Insert burndown invocation immediately before the final hand-off to `finishing-a-development-branch`.

- [ ] **Step 1: Find the anchor — the "Read plan, extract all tasks" first step in the diagram and prose**

Run: `grep -n "Read plan\|finishing-a-development-branch\|^## " skills/subagent-driven-development/SKILL.md`
Expected: find the entry-point step and the final hand-off reference.

- [ ] **Step 2: Add skip detection and diff_base capture at the top**

Use Edit to add a "## Pre-flight" section near the top of the skill (before "## When to Use" or its equivalent):

```markdown
## Pre-flight

Two things must happen before any Task call is issued:

1. **Burndown skip detection.** Check whether the user has expressed an intent to skip the burndown review for this run. Treat ambiguous intent as not skipping. Set `burndown_skip` accordingly.
2. **Capture `diff_base`.** Verify the working tree is clean (`git status --porcelain` returns empty). If not, prompt the user to commit or stash and abort the run if neither happens. Once clean, record the current `HEAD` SHA: `diff_base = $(git rev-parse HEAD)`. This SHA is passed verbatim to burndown-reviews later — by the time burndown runs, the tree will have advanced, but `diff_base` stays anchored to the pre-impl state.
```

- [ ] **Step 3: Insert the burndown invocation before the final hand-off**

Find the line(s) describing the transition to `finishing-a-development-branch`. Use Edit to insert immediately before it:

```markdown
## Burndown Review Pass

After all per-task implementer/reviewer loops complete and tests pass, and before invoking `finishing-a-development-branch`:

If `burndown_skip` is true (re-check intent here; last-write wins): skip this section.

Otherwise: collect the list of files touched during this SDD run into `diff_paths`. Invoke the `burndown-reviews` skill with `stage=impl`, `artifact_path=<repo root>`, `predecessor={ plan_path, diff_base, diff_paths }`, `fixer_model=opus`. Wait for the loop to terminate. The trajectory report is shown to the user as part of its return.
```

- [ ] **Step 4: Verify the file is well-formed**

Run: `grep -c "^## " skills/subagent-driven-development/SKILL.md`
Expected: count goes up by 2 vs. baseline (Pre-flight + Burndown Review Pass).

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "subagent-driven-development: pre-flight diff_base capture and burndown review pass"
```

---

## Chunk 4: Tests

### Task 7: Skill-triggering test

**Files:**
- Create: `tests/burndown-reviews/run-triggering-test.sh`
- Create: `tests/burndown-reviews/triggering-prompt.txt`

The skill-triggering test mirrors the pattern in `tests/skill-triggering/`. It uses a naive prompt that should activate the parent skill, which should then invoke burndown-reviews via its checklist. The test passes if Claude's output references invoking burndown-reviews.

- [ ] **Step 1: Create the prompt fixture**

```bash
mkdir -p tests/burndown-reviews
```

Then create `tests/burndown-reviews/triggering-prompt.txt`:

```
I want to brainstorm a small feature: a CLI flag for our deploy tool that prints which environment it's about to push to and prompts for confirmation. Help me design this.
```

- [ ] **Step 2: Write the failing test script**

Create `tests/burndown-reviews/run-triggering-test.sh`:

```bash
#!/usr/bin/env bash
# Test that brainstorming, when activated, invokes burndown-reviews
# in its checklist.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/tmp/superpowers-tests/${TIMESTAMP}/burndown-reviews-triggering"
mkdir -p "$OUTPUT_DIR"

PROMPT=$(cat "$SCRIPT_DIR/triggering-prompt.txt")

echo "=== Burndown Reviews Triggering Test ==="
echo "Output dir: $OUTPUT_DIR"

# Run claude with brainstorming-trigger prompt; cap turns to keep it cheap.
# We're not running the full brainstorm — just checking that brainstorming's
# checklist now includes a "burndown review pass" step Claude would announce.
claude -p \
  --max-turns 5 \
  --append-system-prompt "$(cat <<'EOF'
You are operating with the superpowers plugin loaded. When the user asks for help designing or brainstorming, invoke the brainstorming skill, read its full checklist, and announce the steps you intend to follow before starting. Do not begin actually asking design questions.
EOF
)" \
  "$PROMPT" > "$OUTPUT_DIR/output.txt" 2>&1

# Pass condition: Claude's output references "burndown review pass" or
# "burndown-reviews" — the new checklist step.
if grep -qiE "burndown[- ]review" "$OUTPUT_DIR/output.txt"; then
  echo "PASS: brainstorming announced the burndown review pass step"
  exit 0
else
  echo "FAIL: brainstorming did not announce a burndown review pass step"
  echo "Output:"
  cat "$OUTPUT_DIR/output.txt"
  exit 1
fi
```

```bash
chmod +x tests/burndown-reviews/run-triggering-test.sh
```

- [ ] **Step 3: Run the test against the unmodified parent skill (sanity check it would FAIL pre-Task-4)**

This step is informational; if Tasks 4-6 have already been committed, the test should now pass. If running pre-integration, expect FAIL. Skip this step if Tasks 4-6 are already committed.

- [ ] **Step 4: Run the test post-integration to verify PASS**

Run: `tests/burndown-reviews/run-triggering-test.sh`
Expected output: `PASS: brainstorming announced the burndown review pass step`

- [ ] **Step 5: Commit**

```bash
git add tests/burndown-reviews/run-triggering-test.sh tests/burndown-reviews/triggering-prompt.txt
git commit -m "Add burndown-reviews skill-triggering test"
```

### Task 8: Manual verification fixtures + procedure

**Files:**
- Create: `tests/burndown-reviews/MANUAL-VERIFICATION.md`
- Create: `tests/burndown-reviews/fixtures/flawed-spec.md`
- Create: `tests/burndown-reviews/fixtures/clean-spec.md`

Full end-to-end verification (running the actual loop with real subagent dispatches) is expensive — multiple subagent calls per round, several minutes per run. We document a manual procedure and provide fixture inputs rather than automating an expensive integration test.

- [ ] **Step 1: Create the deliberately-flawed fixture spec**

Create `tests/burndown-reviews/fixtures/flawed-spec.md`:

```markdown
# Flawed Test Spec

## Motivation

Build a thing that does stuff for users.

## Architecture

The system uses a database. The cache layer reads from the database. The database also reads from the cache. (Two-way data flow — known issue, see below.)

## Components

- **API server** — handles requests
- **Worker** — handles requests

## Data flow

Requests flow from the API server to the database to the cache to the worker, then back. Both reads and writes go through every layer.

## Success criteria

- It works
- Users are happy

## Open questions

TBD
```

The fixture has multiple obvious flaws: vague motivation, contradictory architecture (two-way DB↔cache flow), duplicated component responsibilities, undefined data flow direction, untestable success criteria, and an unresolved TBD. A correct burndown run should converge on a tightened version in 2-4 rounds.

- [ ] **Step 2: Create the clean fixture spec**

Create `tests/burndown-reviews/fixtures/clean-spec.md`:

```markdown
# Hello World CLI Spec

## Motivation

A 30-line educational example: print "Hello, World!" to stdout and exit 0.

## Architecture

A single file `hello.py` containing a `main()` function. Entry point invoked via `if __name__ == "__main__": main()`.

## Success criteria

- `python hello.py` prints exactly `Hello, World!\n` to stdout
- Exit status 0
- No stderr output

## Out of scope

- CLI flags
- Internationalization
- Configuration

## Test

`python hello.py | diff - <(echo "Hello, World!")` produces empty output.
```

The clean fixture is deliberately small and unambiguous; a correct burndown run should declare it clean in round 1 (no findings).

- [ ] **Step 3: Document the manual verification procedure**

Create `tests/burndown-reviews/MANUAL-VERIFICATION.md`:

```markdown
# Burndown Reviews Manual Verification

End-to-end verification runs real subagent dispatches and is expensive — not appropriate for CI. Run on demand when changes touch the loop logic.

## Setup

Fixtures live under `tests/burndown-reviews/fixtures/`.

## Procedure 1: Deliberately-flawed fixture

1. Copy `fixtures/flawed-spec.md` to a scratch location: `cp fixtures/flawed-spec.md /tmp/flawed.md`.
2. Create a minimal context file: `echo "Test fixture for manual verification." > /tmp/flawed.context.md`.
3. Invoke a fresh Claude session with superpowers loaded.
4. Prompt: `Run the burndown-reviews skill on /tmp/flawed.md, with stage=spec, predecessor=/tmp/flawed.context.md, fixer_model=sonnet.`

Expected behavior:
- Round 1 finds H or M findings (vague motivation, architectural contradiction, duplicated components, etc.).
- Subsequent rounds converge: finding count decreases each round.
- Loop returns "clean" before round 7, OR hits round 8 inventory with a non-empty residual.
- Final trajectory report is emitted with at least one round showing >0 findings.

If the loop fails to converge (round 8 hard escalate with most original issues still flagged) or the trajectory report is missing, that's a regression.

## Procedure 2: Clean fixture

Same setup with `fixtures/clean-spec.md`.

Expected behavior:
- Round 1 returns "No findings" from both reviewers.
- Loop returns "clean" immediately.
- Trajectory report shows a single row with 0 findings and a Σ totals row.

If round 1 produces non-trivial findings on the clean fixture, the reviewer rubric or per-stage focus may be too strict.

## Procedure 3: Disagreement escalation

Modify `fixtures/flawed-spec.md` to include a deliberate ambiguity that the orchestrator could plausibly disagree with a reviewer about (e.g., a section labeled "DELIBERATE_ESCALATION_TRIGGER" with a comment explaining what verdict to test). Run as in Procedure 1, watch for the orchestrator to surface a disagreement to the user.
```

- [ ] **Step 4: Commit**

```bash
git add tests/burndown-reviews/MANUAL-VERIFICATION.md tests/burndown-reviews/fixtures/
git commit -m "Add burndown-reviews fixtures and manual verification procedure"
```

---

## Chunk 5: Versioning & Release

### Task 9: Bump package.json version

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Read current version**

Run: `cat package.json`
Expected: shows `"version": "5.0.7"`.

- [ ] **Step 2: Update version to `5.0.7+btc.1`**

Use Edit to replace `"version": "5.0.7"` with `"version": "5.0.7+btc.1"`.

(Build metadata `+btc.1` does not affect semver precedence — the fork is not seen as "older" than upstream.)

- [ ] **Step 3: Verify**

Run: `cat package.json`
Expected: shows `"version": "5.0.7+btc.1"`.

- [ ] **Step 4: Commit**

```bash
git add package.json
git commit -m "Bump version to 5.0.7+btc.1"
```

### Task 10: Add RELEASE-NOTES entry

**Files:**
- Modify: `RELEASE-NOTES.md`

- [ ] **Step 1: Read the current top of RELEASE-NOTES**

Run: `head -10 RELEASE-NOTES.md`
Expected: shows the title and the most recent entry (`## v5.0.7 ...`).

- [ ] **Step 2: Insert a new entry above the v5.0.7 entry**

Use Edit to add (right after `# Superpowers Release Notes`):

```markdown

## v5.0.7+btc.1 (2026-05-04) — Fork divergence

This is a fork release on `btc/superpowers`, layered on top of upstream v5.0.7. Build-metadata suffix `+btc.1` keeps the fork from sorting below upstream in semver comparisons.

### Burndown Reviews

A new skill `burndown-reviews` runs at the spec, plan, and impl checkpoints (between artifact write and the existing user-review gate). Two reviewer subagents (Opus + Sonnet) review concurrently per round; the orchestrator judges each finding and applies a fixer subagent to the accepted set. Up to 7 rounds, then a round-8 reviewer-only inventory pass on hard-escalate. The user is only pulled in when the orchestrator can't confidently override or accept a reviewer's finding.

- New skill: `skills/burndown-reviews/SKILL.md`
- New agents: `agents/burndown-reviewer.md`, `agents/burndown-fixer.md`
- Integration: `brainstorming`, `writing-plans`, `subagent-driven-development` each gain a burndown-review pass before their user-review step.
- Voice tunables: "skip the burndown for this one" (parent skill detects), "run more rounds" (after hard-escalate), fixer-model override (mid-loop, last-write wins).
- Trajectory report emitted at every loop termination.

Spec: `docs/superpowers/specs/2026-05-04-burndown-reviews-design.md`. Plan: `docs/superpowers/plans/2026-05-04-burndown-reviews.md`.
```

- [ ] **Step 3: Verify the file**

Run: `head -25 RELEASE-NOTES.md`
Expected: shows the new entry above the v5.0.7 entry.

- [ ] **Step 4: Commit**

```bash
git add RELEASE-NOTES.md
git commit -m "RELEASE-NOTES: v5.0.7+btc.1 fork divergence entry"
```

### Task 11: Push the branch

- [ ] **Step 1: Push burndown-reviews branch to origin**

Run: `git push origin burndown-reviews`
Expected: branch updated on `btc/superpowers` GitHub remote.

---

## Chunk 6: Marketplace Repo (independent of superpowers fork)

This chunk creates a separate repo `btc/claude-plugins` containing a `marketplace.json` file. The marketplace points the `superpowers` plugin at the fork, allowing `/plugin install superpowers@btc-plugins` to work.

### Task 12: Create the marketplace repo locally

- [ ] **Step 1: Create the directory and initialize git**

```bash
mkdir -p ~/Projects/src/claude-plugins/.claude-plugin
cd ~/Projects/src/claude-plugins
git init
```

- [ ] **Step 2: Write a minimal README**

Create `~/Projects/src/claude-plugins/README.md`:

```markdown
# btc/claude-plugins

A small Claude Code plugin marketplace. Currently hosts a single plugin: a fork of [obra/superpowers](https://github.com/obra/superpowers) with a `burndown-reviews` skill that adds multi-model subagent review at the spec, plan, and impl checkpoints.

## Install

```text
/plugin marketplace add btc/claude-plugins
/plugin install superpowers@btc-plugins
```

If you currently have upstream superpowers installed, uninstall it first:

```text
/plugin uninstall superpowers@claude-plugins-official
```

## Source

The fork lives at https://github.com/btc/superpowers (branch `burndown-reviews`).
```

- [ ] **Step 3: Write the marketplace.json**

Create `~/Projects/src/claude-plugins/.claude-plugin/marketplace.json`:

```json
{
  "name": "btc-plugins",
  "owner": "btc",
  "description": "btc's personal plugins for Claude Code",
  "plugins": [
    {
      "name": "superpowers",
      "description": "Fork of obra/superpowers with burndown-reviews — multi-model subagent review at the spec, plan, and impl checkpoints.",
      "category": "development",
      "source": {
        "source": "url",
        "url": "https://github.com/btc/superpowers.git"
      }
    }
  ]
}
```

- [ ] **Step 4: Initial commit**

```bash
cd ~/Projects/src/claude-plugins
git add .
git commit -m "Initial: btc-plugins marketplace with superpowers fork"
```

### Task 13: Push the marketplace repo to GitHub

- [ ] **Step 1: Create the remote (public repo)**

```bash
cd ~/Projects/src/claude-plugins
gh repo create btc/claude-plugins --public --source=. --remote=origin --description="btc's personal plugins for Claude Code"
```

- [ ] **Step 2: Push**

```bash
git push -u origin main
```

- [ ] **Step 3: Verify**

Run: `gh repo view btc/claude-plugins --web` (or visit `https://github.com/btc/claude-plugins`).
Expected: repo exists, public, contains README and `.claude-plugin/marketplace.json`.

### Task 14: End-to-end install verification

- [ ] **Step 1: Add the marketplace in Claude Code**

In a Claude Code session: `/plugin marketplace add btc/claude-plugins`
Expected: marketplace added; `/plugin` lists `superpowers` from `btc-plugins`.

- [ ] **Step 2: Uninstall upstream and install fork**

`/plugin uninstall superpowers@claude-plugins-official`
`/plugin install superpowers@btc-plugins`

Expected: fork installs; `/plugin` shows `superpowers@btc-plugins` at version `5.0.7+btc.1`.

- [ ] **Step 3: Smoke-test in a fresh session**

Open a new Claude Code session; the `using-superpowers` skill bootstrap should load with the new burndown-reviews skill listed in available skills.

Expected: `burndown-reviews` appears in the user-invocable skills list.

---

## Self-Review

After all tasks are complete, run a final pass:

**Spec coverage check:**
- New skill ✓ (Task 3 — burndown-reviews/SKILL.md)
- Reviewer agent ✓ (Task 1)
- Fixer agent ✓ (Task 2)
- Brainstorming integration ✓ (Task 4)
- Writing-plans integration ✓ (Task 5)
- SDD integration with diff_base capture ✓ (Task 6)
- Skip detection (per-skill, ambiguous-as-not-skipping) ✓ (Tasks 4, 5, 6)
- Voice tunables (run more rounds, fixer override) ✓ (Task 3 includes both)
- Trajectory report ✓ (Task 3 includes the table format)
- Round-8 inventory pass with carried-deferred labeling ✓ (Task 3)
- Failure modes (retries, fatal abort, deferred findings, new files, deletions) ✓ (Task 3 references the spec)
- Tests ✓ (Tasks 7, 8)
- Versioning + release notes ✓ (Tasks 9, 10)
- Marketplace repo ✓ (Tasks 12, 13)
- Install verification ✓ (Task 14)

**Open question 1 (exact step numbers in writing-plans and SDD):** resolved during implementation by reading the current skill files at Task 5/6 time. The plan's anchor instructions (`grep -n "^## "`) tell the implementer where to look.

**Open question 2 (test harness specifics):** resolved by adapting the spec's "orchestrator-simulation tests" to the codebase's bash + claude-CLI convention. Skill-triggering test (cheap, automated) + fixture-based manual verification procedure (gated, on-demand). Documented at the top of this plan.

**No-placeholder check:** every step contains either an exact code block, an exact command, or a concrete instruction. No "TBD" or "fill in later".

**Type-consistency check:** field names used across tasks (`burndown_skip`, `diff_base`, `diff_paths`, `fixer_model`, `predecessor`, `stage`, `artifact_path`, `deferred`, `created_paths`, `deleted_paths`) are used identically in the agent files (Tasks 1, 2), the skill file (Task 3), and the integration edits (Tasks 4, 5, 6). The agent file inputs match the skill's dispatch contract.
