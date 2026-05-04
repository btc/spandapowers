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

**NOTE on fences:** the agent file content below contains a nested 3-backtick code block (the output format example). When passing this to the Write tool, use a 4-backtick outer fence (` ```` `) so the inner 3-backtick fences don't terminate the outer block prematurely.

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

- **Prose artifacts (spec, plan):** `<path> § "<H2>" / "<H3>" / ...` — the **full heading chain** from the H2 down to the section containing the issue. Examples: `spec.md § "Architecture" / "Failure modes"` (two-level), `spec.md § "Reviewer subagent" / "Inputs"` (two-level), `spec.md § "Architecture" / "The loop" ¶3` (two-level + paragraph index). Top-level sections use a single heading: `spec.md § "Architecture"`. The chain disambiguates section names that recur under different parents.
- **Pre-H2 / preamble content:** `<path> § (preamble)` — for content under H1 with no H2, or content above the first H2.
- **Fenced code blocks within prose:** `<path> § "<H2>" / "<H3>" code-block:L<n>` where `L<n>` is the line number relative to the start of the code block.
- **Code artifacts (impl):** `<path>:L<start>-L<end>` — e.g., `src/loop.ts:L42-58`. Single-line issues: `src/loop.ts:L42`.
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
  Applies a reconciled finding list to a Superpowers-driven artifact. Dispatched by the burndown-reviews skill; the orchestrator picks the model at dispatch time (opus for all stages; overridable by user voice).
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
- `fixer_model` — `opus` for all stages. Overridable by user voice.
- `stage` — `spec` | `plan` | `impl`

## Spec

Authoritative behavior is defined in `docs/superpowers/specs/2026-05-04-burndown-reviews-design.md`. This skill file is the operational checklist; consult the spec for the why and the edge cases.
```

- [ ] **Step 2: Append the loop execution checklist**

Append to the same file. **NOTE on fences:** the SKILL.md content below contains nested triple-backtick code blocks. When passing this content to the Write or Edit tool, use a 4-backtick outer fence (` ```` `) for the heredoc / Edit `new_string` to avoid premature termination by the inner 3-backtick blocks. Or split into two Edit calls (one for each prose-+-code segment).

```markdown
## Loop execution

Initialize once before the loop:

```
deferred_findings = []
prev_deferred_id_set = None
prev_artifact_hash = None
abort_error = None
fixer_model_for_stage = opus   # all stages; overridable by user voice
   # (last-write wins — see "Voice tunables")
```

For each round 1 through 7:

1. **A. Dispatch reviewers concurrently** — issue both Task calls in a single message with the `burndown-reviewer` agent, one with `model=opus`, one with `model=sonnet`. Pass `stage`, `artifact_path`, and the predecessor context. Both run in parallel.
2. **B. Stamp finding IDs post-hoc** — namespace each reviewer's sequential IDs as `opus-r{round}-{n}` and `sonnet-r{round}-{n}`. Concatenate Opus output, Sonnet output, and the prior round's `deferred_findings` (which retain their original older IDs) into one `all_findings` list.
3. **C. Judge each finding** — for each entry in `all_findings`, choose one of three verdicts:
   - **Accept** — finding is real and the suggested fix is sound. Add to `fix_list`.
   - **Override** (confident) — you can verify the reviewer is wrong against the spec, the artifact, or the locked decisions. Drop silently; do not escalate. The user's time is the scarce resource you are protecting.
   - **Escalate** (uncertain) — you suspect the reviewer is wrong but cannot fully verify, or the call genuinely depends on user judgment. Add to `disagreements`.
4. **D. Merge near-duplicates** — collapse `fix_list` and `disagreements` **independently** (never across the two lists). Same merge rules apply to both:
   - **Location match** — same full heading chain (prose) or overlapping line range (code; merged location = union, smallest start to largest end).
   - **Severity adjacency** — H↔M mergeable, M↔L mergeable, H↔L NOT mergeable (non-transitive). Merged severity = max of the two.
   - **ID survival** — when a deferred finding (carrying older ID) merges with a fresh finding, retain the **older** deferred ID for traceability. When two fresh findings of the same round merge, pick either.
   - **Fix-list match** uses `suggested_fix` similarity (same intervention?). **Disagreement-list match** uses `claim` similarity (the user is choosing what to do, so contradictory fix text is informative).
   - **Conflicting fixes at same location in fix_list:** the orchestrator must NEVER pass two contradictory `suggested_fix` strings to the fixer. Pick one and override or escalate the other; or, if the fixes are genuinely complementary, author a synthesized fix instruction in your own words and **log it in the round summary** so the rewrite is auditable. Prefer pick-one over rewriting.
5. **E. Pause if any escalated disagreements remain** — surface them to the user in plain language, batched per round. Use the Disagreement UX from the spec (state finding, explain disagreement, offer recommendation, listen, restate). Block until the user finishes resolving every escalated item. Add user-resolved "keep" findings to `fix_list` (with the user's text replacing the reviewer's `suggested_fix` if they wrote one).
6. **F. Early-clean check** — if `fix_list` is empty, return "clean" and emit the trajectory report. (User-skipped escalations and orchestrator overrides both count as cleared.)
**Before round 1's reviewer dispatch (also at each disagreement-pause and during round-8 hard-escalate):** check for a fixer-model voice override. If the user has said something like "use sonnet for fixer this round" or "switch fixer to opus," update `fixer_model_for_stage` accordingly. Last-write wins.

7. **G. Dispatch the fixer subagent** — single Task call with the `burndown-fixer` agent and `model=fixer_model_for_stage`. Pass `artifact_path`, the reconciled `fix_list`, and `stage` (plus `diff_paths` and `diff_base` for impl). Verify content changed via sha256 hash before/after, with these legitimacy rules:
   - **Hash domain:** for prose artifacts (spec, plan), hash the artifact file's full bytes. For impl stage, hash the concatenated full contents of files in `diff_paths` (sorted by path), treating any deleted file's contents as empty bytes — so deletions register as a real content change rather than a hash collision.
   - **Unchanged content + non-empty deferred list = legitimate.** The fixer determined it could apply none of the findings cleanly. Do NOT retry; advance to round N+1 with the deferred list carried forward.
   - **Unchanged content + empty deferred list + non-empty fix_list = failure.** Retry once. If still unchanged, set `abort_error` and break (fatal abort).
   - **New-files exemption:** if `fixer_result.created_paths` is non-empty, skip the unchanged-content failure check for this round entirely — the new-file report is itself authoritative evidence the fixer did work. Extend in-loop `diff_paths` with the new paths.
   - **Reviewer/fixer crash retry:** any reviewer or fixer crash retries once within the same round (does not consume a round slot). Two consecutive crashes → fatal abort.
   - **Conflicting fixes never reach the fixer:** before this dispatch, the merge step (D) must have ensured that two contradictory `suggested_fix` strings at the same location were resolved (orchestrator picks one, escalates the other, or authors a logged rewrite). The fixer must never receive contradictory instructions for the same location.
   On fatal abort, set `abort_error = fixer_result.error` and break out of the loop — round 8 still runs (the user gets the abort error alongside a current-state finding list).
8. **H. Update `deferred_findings`** from `fixer_result.deferred` (replaces, not appends — earlier-round deferrals were already re-judged in step C). Update in-loop `diff_paths` from `fixer_result.created_paths` (extend) and `fixer_result.deleted_paths` (remove). Compute the current artifact hash and deferred-ID set; if both equal the prior round's values and the deferred set is non-empty, break out of the loop early (non-progress short-circuit).

After the loop (round 8 — inventory pass):

- Dispatch both reviewers concurrently with the same inputs as in step A. Stamp findings with the **actual round number** the loop terminated at: typically `opus-r8-{n}` / `sonnet-r8-{n}` for the initial inventory; `opus-r{N}-{n}` / `sonnet-r{N}-{n}` for a post-extension inventory (e.g., `r18` after 10 extension rounds concluding at round 18). Do NOT hardcode `r8` for post-extension inventory passes.
- Merge `final_opus + final_sonnet + deferred_findings` using the in-loop merge rules. Carried-deferred entries keep older IDs and get a `[deferred since r{N}]` annotation in the user-facing surface.
- Termination logic — three cases:
  - `residual` empty AND `abort_error` is None → return "clean".
  - `abort_error` is not None (regardless of residual size) → surface the abort error AND the residual list together; mark as hard_escalate-with-abort.
  - `residual` non-empty AND `abort_error` is None → surface the residual with: "7 rounds didn't converge. Here's what's still flagged. Accept as-is, run more rounds, or fix manually?"

**High-escalation-rate edge case (within the loop):** if the orchestrator finds itself escalating an unusually large fraction of findings in a single round, that's a signal of miscalibration. For round 1, "unusual" = more than half of all findings escalated. For round 2+, "unusual" = significantly above the run's prior-round cadence. When triggered, the orchestrator pauses and offers the user three concrete options: (a) skip remaining escalations this round (treat as confident overrides), (b) abort the loop so the user can edit the reviewer agent definition and restart, or (c) keep going as-is.

After every termination (clean, hard escalate, or fatal abort): emit the trajectory report (see "Trajectory report" below).

## Voice tunables

Listen for these intents:

- **"Run more rounds"** — after a hard-escalate. The user specifies a number; restart the inner loop fresh (`deferred_findings = []`, `abort_error = None`, trackers reset) for that many rounds, with sequential numbering (round 9, 10, ...). After exhaustion, run another inventory pass with the actual round number.
- **Override the fixer model** — listen for phrases like "use sonnet for fixer this round", "switch fixer to opus", "go cheaper for the fixer". Detected at three points: (i) at the start of round 1, before the first reviewer dispatch; (ii) on each disagreement-pause; (iii) during the round-8 hard-escalate exchange. Last-write wins. Update `fixer_model_for_stage` immediately; the new value applies to all subsequent fixer dispatches.

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
8. **Burndown review pass (NEW)** — if `burndown_skip` is true (re-check intent here; last-write wins), skip this step. Otherwise: write `<artifact_basename>.context.md` alongside the spec containing a best-effort summary of the user's original request, locked-in design decisions, and explicit non-goals (sections may be empty if not produced during the brainstorm). Then invoke the `burndown-reviews` skill with `stage=spec`, `artifact_path=<spec path>`, `predecessor=<context file path>`, `fixer_model=opus`. Wait for the loop to terminate. The loop's trajectory report goes to the user as part of its return.
9. User reviews written spec
10. Transition to implementation

Use Edit to replace the existing 8-step list with this 10-step list. Preserve formatting.

- [ ] **Step 4: Update the Process Flow dot diagram**

The brainstorming SKILL.md contains a `dot` digraph diagram of the process flow. First confirm the diagram exists:

```bash
grep -n 'digraph brainstorming\|"Spec self-review' skills/brainstorming/SKILL.md
```

If the diagram exists (it does in the upstream version of the file), make these exact edits:

Add a new node declaration alongside the others:

```dot
"Burndown review pass" [shape=box];
```

Replace the existing edge:

```dot
"Spec self-review\n(fix inline)" -> "User reviews spec?";
```

with two new edges:

```dot
"Spec self-review\n(fix inline)" -> "Burndown review pass";
"Burndown review pass" -> "User reviews spec?";
```

If the diagram does not exist (e.g., the upstream skill changed and removed it), skip this step and note it in the commit message.

- [ ] **Step 5: Verify the file still parses as well-formed markdown**

A bare `grep -c "^[0-9]\+\. "` would also count any other numbered lists in the file. Anchor the count to the Checklist section only:

```bash
awk '/^## Checklist/,/^## [^C]/' skills/brainstorming/SKILL.md | grep -c "^[0-9]\+\. "
```

Expected: `10` (10 numbered checklist items in the Checklist section). Also confirm the new step is present:

```bash
grep -n "Burndown review pass" skills/brainstorming/SKILL.md
```

Expected: at least one match.

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

- [ ] **Step 1: Find the anchor and capture baseline**

```bash
grep -n "^## " skills/writing-plans/SKILL.md
BASELINE_WP=$(grep -c "^## " skills/writing-plans/SKILL.md)
echo "Baseline H2 count: $BASELINE_WP"
```

Expected output includes `## Self-Review` and `## Execution Handoff`. Record the baseline H2 count for verification after edits (Step 4).

- [ ] **Step 2: Add skip detection immediately before the `## Scope Check` heading**

The Overview section's last content is the `**Save plans to:**` line. Insert the skip-detection note as a new paragraph just before `## Scope Check` (so it lives at the very top of the actionable content, after Overview):

```markdown
**Burndown skip detection (always first):** Before starting plan-writing, check whether the user has expressed an intent to skip the burndown review for this run (e.g., "skip the burndown for this one"). Treat ambiguous intent ("maybe skip it") as not skipping (conservative default). Set `burndown_skip = true` if a clear skip intent is detected; otherwise leave it unset.
```

- [ ] **Step 3: Insert the burndown invocation between Self-Review and Execution Handoff**

Use Edit to insert a new section between `## Self-Review` and `## Execution Handoff`:

```markdown
## Burndown Review Pass

After the inline self-review passes, and before the Execution Handoff:

If `burndown_skip` is true (re-check intent here; last-write wins): skip this section.

Otherwise: invoke the `burndown-reviews` skill with `stage=plan`, `artifact_path=<plan file path>`, `predecessor=<spec file path>`, `fixer_model=opus`. Wait for the loop to terminate. The trajectory report is shown to the user as part of its return.
```

- [ ] **Step 4: Verify the file is well-formed**

```bash
NEW_WP=$(grep -c "^## " skills/writing-plans/SKILL.md)
echo "New H2 count: $NEW_WP (expected: $((BASELINE_WP + 1)))"
[ "$NEW_WP" -eq "$((BASELINE_WP + 1))" ] && echo "OK" || echo "MISMATCH"
```

Expected: `OK` (one new H2 added: `## Burndown Review Pass`).

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

- [ ] **Step 1: Find the anchors and capture baseline**

```bash
grep -n "^## " skills/subagent-driven-development/SKILL.md
grep -n "Read plan\|finishing-a-development-branch" skills/subagent-driven-development/SKILL.md
BASELINE_SDD=$(grep -c "^## " skills/subagent-driven-development/SKILL.md)
echo "Baseline H2 count: $BASELINE_SDD"
```

Expected: H2 list shows `## When to Use` and `## The Process` early; the final hand-off to `finishing-a-development-branch` appears later in the file. Record the baseline H2 count for verification after edits (Step 4).

- [ ] **Step 2: Add Pre-flight section after "When to Use", before "The Process"**

The SDD skill begins with `## When to Use` (a decision-tree diagram about whether SDD is the right skill). The Pre-flight check should run AFTER SDD has been chosen as the right skill but BEFORE any Task call is issued — i.e., between `## When to Use` and `## The Process`.

Find the exact insertion line:

```bash
grep -n "^## " skills/subagent-driven-development/SKILL.md
```

Identify the line numbers of `## When to Use` and `## The Process`. Insert the new `## Pre-flight` section between them (immediately before `## The Process`).

Use Edit to insert this section:

```markdown
## Pre-flight

Two things must happen before any Task call is issued (i.e., before "The Process" begins):

1. **Burndown skip detection.** Check whether the user has expressed an intent to skip the burndown review for this run (e.g., "skip the burndown for this one"). Treat ambiguous intent ("maybe skip it") as not skipping (conservative default, no silent guessing). If a clear skip intent is detected, set `burndown_skip = true`; otherwise leave it unset.
2. **Capture `diff_base`.** Verify the working tree is clean (`git status --porcelain` returns empty). If it is not clean:
   - Surface the issue to the user with a brief summary of what's uncommitted (`git status --short`) and prompt: "Working tree is not clean. Commit or stash before continuing? (commit / stash / abort)"
   - If the user chooses commit or stash, wait for them to do so and re-check.
   - If the user chooses abort (or declines both options), **stop SDD execution by surfacing the precondition failure to the user and exiting the skill without dispatching any tasks**. Do not silently proceed.
   Once the tree is clean, record the current `HEAD` SHA: `diff_base = $(git rev-parse HEAD)`. This SHA is passed verbatim to burndown-reviews later — by the time burndown runs, the tree will have advanced, but `diff_base` stays anchored to the pre-impl state.
```

- [ ] **Step 3: Insert the burndown invocation before the final hand-off**

Find the line(s) describing the transition to `finishing-a-development-branch`. Use Edit to insert immediately before it:

```markdown
## Burndown Review Pass

After all per-task implementer/reviewer loops complete and tests pass, and before invoking `finishing-a-development-branch`:

If `burndown_skip` is true (re-check intent here; last-write wins): skip this section.

Otherwise: collect the list of files touched during this SDD run via:

`diff_paths=$(git diff --name-only $diff_base HEAD)`

Then invoke the `burndown-reviews` skill with `stage=impl`, `artifact_path=<repo root>`, `predecessor={ plan_path, diff_base, diff_paths }`, `fixer_model=opus`. Wait for the loop to terminate. The trajectory report is shown to the user as part of its return.
```

- [ ] **Step 4: Verify the file is well-formed**

```bash
NEW_SDD=$(grep -c "^## " skills/subagent-driven-development/SKILL.md)
echo "New H2 count: $NEW_SDD (expected: $((BASELINE_SDD + 2)))"
[ "$NEW_SDD" -eq "$((BASELINE_SDD + 2))" ] && echo "OK" || echo "MISMATCH"
```

Expected: `OK` (two new H2s added: `## Pre-flight` and `## Burndown Review Pass`).

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "subagent-driven-development: pre-flight diff_base capture and burndown review pass"
```

---

## Chunk 4: Tests

### Task 7: Skill-triggering test (uses existing harness)

**Files:**
- Create: `tests/skill-triggering/prompts/burndown-reviews.txt`
- Modify: `tests/skill-triggering/run-all.sh` (add `burndown-reviews` to the `SKILLS` array)

The codebase already has a skill-triggering harness at `tests/skill-triggering/run-test.sh` that uses `claude -p` with `--plugin-dir`, `--dangerously-skip-permissions`, `--output-format stream-json`, and detects skill invocation via JSON pattern matching on `"name":"Skill"` + `"skill":"<name>"`. This task plugs into that harness rather than duplicating it.

The test verifies that `burndown-reviews` is triggered when a parent skill (brainstorming) reaches its checklist's burndown step. Because the harness only runs the prompt for `MAX_TURNS` (default 3), and brainstorming starts by asking clarifying questions before the burndown step, the prompt must give Claude enough context to skip ahead to a phase where burndown-reviews would be invoked. We do that by phrasing the prompt as a request that *resumes* a brainstorm at the spec-self-review checkpoint.

- [ ] **Step 1: Create the prompt fixture**

Create `tests/skill-triggering/prompts/burndown-reviews.txt`:

```
I've just finished brainstorming a tiny feature with you and the spec is at /tmp/example-spec.md. The brainstorming checklist's spec-self-review step is done. What's the very next step in the brainstorming checklist, and what skill does it invoke?
```

This phrasing forces Claude to consult the brainstorming skill's checklist, identify the burndown step, and (per skill conventions) actually invoke `burndown-reviews` as the next step.

- [ ] **Step 2: Add `burndown-reviews` to the SKILLS array in run-all.sh**

Read the file first to find the array:

```bash
grep -n "^SKILLS=\|^SKILLS_ARR\|burndown-reviews\|^[[:space:]]*\"writing-plans\"" tests/skill-triggering/run-all.sh
```

Use the Edit tool to add `"burndown-reviews"` to the `SKILLS` array, alphabetically before `"dispatching-parallel-agents"` (or wherever fits the existing ordering).

- [ ] **Step 3: Run the test**

Run: `tests/skill-triggering/run-test.sh burndown-reviews tests/skill-triggering/prompts/burndown-reviews.txt`

Expected: the harness prints `✅ PASS: Skill 'burndown-reviews' was triggered`.

If FAIL: the brainstorming integration in Task 4 may not be wired correctly, or the prompt phrasing didn't successfully push Claude past the early-conversation phase. Adjust the prompt or revisit Task 4 before proceeding.

- [ ] **Step 4: Run the full skill-triggering suite to verify nothing else regressed**

Run: `tests/skill-triggering/run-all.sh`

Expected: all skills, including the new `burndown-reviews`, pass.

- [ ] **Step 5: Commit**

```bash
git add tests/skill-triggering/prompts/burndown-reviews.txt tests/skill-triggering/run-all.sh
git commit -m "Add burndown-reviews to skill-triggering test suite"
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

The fixture has multiple obvious flaws: vague motivation, contradictory architecture (two-way DB↔cache flow), duplicated component responsibilities, undefined data flow direction, untestable success criteria, and an unresolved TBD. A correct burndown run should converge before round 7 (return "clean") OR hit round 8 with a meaningfully smaller residual than the round-1 finding count. The exact round count varies per run because reviewers are stateless LLMs.

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
4. Prompt: `Run the burndown-reviews skill on /tmp/flawed.md, with stage=spec, predecessor=/tmp/flawed.context.md, fixer_model=opus.`

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

Create `/tmp/escalation-test-spec.md` with a deliberate orchestrator-vs-reviewer disagreement trigger:

- A section that is locked-in per the context file (e.g., `/tmp/escalation-test.context.md` says "DECISION: use a single-table schema, denormalize aggressively") but the spec body invites the reviewer to flag it as a concern (e.g., "Architecture: single-table schema with deliberate denormalization — this is a known design trade-off chosen for read latency").

Run the burndown procedure as in Procedure 1. Expected behavior:
- A reviewer (likely Sonnet, since Opus tends to respect locked decisions more aggressively) will probably flag the denormalization as an anti-pattern.
- The orchestrator should recognize the context file's lock-in, **override** the finding confidently (no escalation), and continue.

If the orchestrator escalates this to the user instead, that's a regression: the orchestrator-confidence rule isn't being applied. If the orchestrator silently applies the reviewer's fix (rewriting the schema), that's also a regression: the locked decision wasn't preserved.
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

- [ ] **Step 3: Verify the JSON parses and the version round-trips**

```bash
cat package.json
node -e "console.log(require('./package.json').version)"
```

Expected: prints `5.0.7+btc.1`. If `node` rejects the version string or normalizes it (some npm versions historically had quirks with build metadata), surface the issue here rather than at install time. If the build-metadata form is rejected, fall back to `5.0.8-btc.1` (next-patch + pre-release suffix; sorts above `5.0.7`) and update Task 10's RELEASE-NOTES entry to match.

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

Run: `git push -u origin burndown-reviews`

The `-u` flag sets upstream tracking on first push and is a no-op afterwards. Expected: branch updated on `btc/superpowers` GitHub remote. If the push is rejected due to remote divergence, abort and surface the issue — do not force-push without explicit user consent.

---

## Chunk 6: Marketplace Repo (independent of superpowers fork)

This chunk creates a separate repo `btc/claude-plugins` containing a `marketplace.json` file. The marketplace points the `superpowers` plugin at the fork, allowing `/plugin install superpowers@btc-plugins` to work.

### Task 12: Create the marketplace repo locally

- [ ] **Step 1: Create the directory and initialize git**

Use absolute-path-safe commands (don't rely on `cd` persisting across tool calls):

```bash
mkdir -p ~/Projects/src/claude-plugins/.claude-plugin
git -C ~/Projects/src/claude-plugins init
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
git -C ~/Projects/src/claude-plugins add .
git -C ~/Projects/src/claude-plugins commit -m "Initial: btc-plugins marketplace with superpowers fork"
```

### Task 13: Push the marketplace repo to GitHub

- [ ] **Step 1: Create the remote (public repo)**

```bash
gh repo create btc/claude-plugins --public --source=$HOME/Projects/src/claude-plugins --remote=origin --description="btc's personal plugins for Claude Code"
```

- [ ] **Step 2: Push**

```bash
git -C ~/Projects/src/claude-plugins push -u origin main
```

- [ ] **Step 3: Verify**

Run: `gh repo view btc/claude-plugins --web` (or visit `https://github.com/btc/claude-plugins`).
Expected: repo exists, public, contains README and `.claude-plugin/marketplace.json`.

### Task 14: End-to-end install verification

- [ ] **Step 1: Add the marketplace in Claude Code**

In a Claude Code session: `/plugin marketplace add btc/claude-plugins`
Expected: marketplace added; `/plugin` lists `superpowers` from `btc-plugins`.

- [ ] **Step 2: Uninstall upstream (conditional) and install fork**

First check whether upstream superpowers is installed:

```text
/plugin list
```

If `superpowers@claude-plugins-official` appears in the list, uninstall it:

```text
/plugin uninstall superpowers@claude-plugins-official
```

If it does not appear (fresh install), skip the uninstall step.

Then install the fork:

```text
/plugin install superpowers@btc-plugins
```

Expected: fork installs; `/plugin list` shows `superpowers@btc-plugins` at version `5.0.7+btc.1`.

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

**Open question 2 (test harness specifics):** resolved by adapting the spec's "orchestrator-simulation tests" to the codebase's bash + claude-CLI convention. Skill-triggering test (cheap, automated, plugged into the existing `tests/skill-triggering/` harness) + fixture-based manual verification procedure (gated, on-demand). Documented at the top of this plan.

**Test coverage matrix.** The spec's `## Testing / ## Orchestrator-simulation` section enumerates 12 specific test cases. The plan's coverage of each:

| Spec test case                                              | Coverage in this plan                            |
|-------------------------------------------------------------|--------------------------------------------------|
| Two reviewers, identical findings, compatible fixes → merge | Manual Procedure 1 (flawed fixture exercises the merge path) |
| Two reviewers, same location, conflicting fixes             | Manual Procedure 1 (flawed fixture's two-way DB↔cache contradiction) |
| Solo finding, judged like any other                         | Manual Procedure 1 (statelessness produces solos in normal runs) |
| Severity merge: H+M, M+L (mergeable); H+L (not)             | Out of scope — would need a mock-subagent harness to exercise reliably |
| Round-7 boundary, round-8 inventory pass                    | Manual Procedure 1 (flawed fixture, watch round count) |
| Reviewer subagent fails on first call → retry once          | Out of scope — not exercised by any fixture |
| Reviewer subagent fails twice → abort                       | Out of scope                                      |
| Fixer success but content unchanged → retry/abort           | Out of scope                                      |
| Fixer reports deferred findings                             | Out of scope (would need a deliberately-conflicting fixture; not built) |
| Extension after hard escalate, full cycles, sequential numbering | Manual Procedure 1 + user voice "run more rounds" |
| Confident override drops finding without escalation         | Manual Procedure 3 (escalation-trigger fixture)   |
| Deferred-override path, ID retired                          | Out of scope                                      |
| ID-survival merge (older ID retained)                       | Out of scope                                      |
| Non-progress short-circuit                                  | Out of scope                                      |
| Fixer-abort with round 8                                    | Out of scope                                      |

Cases marked "Out of scope" are deferred because they require either (a) a mock-subagent framework that does not exist in this codebase, or (b) deliberately-broken fixtures that are not load-bearing for first-cut deployment. Add coverage in a follow-up if the loop logic regresses in ways the manual procedures miss.

**RELEASE-NOTES vs CHANGELOG:** the spec's File Layout section references `CHANGELOG.md`, but the actual upstream repo has `RELEASE-NOTES.md` (no `CHANGELOG.md`). Task 10 of this plan correctly targets `RELEASE-NOTES.md`. Anyone cross-referencing the spec's file layout should ignore the `CHANGELOG.md` mention — it's a stale spec artifact that should be updated in a follow-up commit. (Optional: append a one-line correction to the spec File Layout section: "(actual file: `RELEASE-NOTES.md`)".)

**No-placeholder check:** every step contains either an exact code block, an exact command, or a concrete instruction. No "TBD" or "fill in later".

**Type-consistency check:** field names used across tasks (`burndown_skip`, `diff_base`, `diff_paths`, `fixer_model`, `predecessor`, `stage`, `artifact_path`, `deferred`, `created_paths`, `deleted_paths`) are used identically in the agent files (Tasks 1, 2), the skill file (Task 3), and the integration edits (Tasks 4, 5, 6). The agent file inputs match the skill's dispatch contract.
