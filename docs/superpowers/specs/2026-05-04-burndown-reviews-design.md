# Burndown Reviews

Add an automated multi-model subagent review loop to the three superpowers checkpoints (post-spec, post-plan, post-impl). The loop runs Opus and Sonnet reviewers concurrently against the artifact, fixes findings round-by-round until the merged finding list is empty or a 7-round cap is hit, and pauses to escalate to the user only when the reviewers genuinely disagree.

## Motivation

Today the superpowers workflow has one user-review gate at the end of each stage: brainstorming writes a spec and asks the user to review; writing-plans writes a plan and asks the user to review; subagent-driven-development completes implementation and asks the user to review. The user is the only quality gate.

For non-trivial artifacts this skips a level of pre-review that a human team would do — having one or two engineers read the artifact and surface issues before the author hands it to a stakeholder. The user winds up doing both the substantive review and the "did I miss anything obvious" pass.

Burndown reviews insert that pre-review pass at all three checkpoints. Two reviewer subagents (Opus and Sonnet) read the artifact in parallel, the orchestrator reconciles their findings, a fixer subagent applies the agreed fixes, and the loop repeats until the artifact is clean or the round cap is hit. The user only sees the final clean artifact — and any genuine disagreements between the reviewers, surfaced in plain language as they happen.

## Scope

This spec covers:

- A new shared skill, `burndown-reviews`, that drives the loop.
- Two new agent definitions: `burndown-reviewer` and `burndown-fixer`.
- Edits to three existing skills (`brainstorming`, `writing-plans`, `subagent-driven-development`) to invoke the new skill at the right checkpoint.
- Fork mechanics: forking `obra/superpowers` to `btc/superpowers`, setting up a small `btc/claude-plugins` marketplace repo, and the install path.
- The sync-with-upstream workflow.
- Tests under `tests/burndown-reviews/`.

This spec does not cover:

- Configuration files, env vars, or `settings.json` keys. Tuning is done by user voice ("skip the burndown for this one", "run more rounds").
- Reviewer state across rounds. Reviewers and fixers are stateless per round.
- Cross-stage learning. The fixer at the plan checkpoint doesn't see the spec checkpoint's review history.
- Per-user customization of the severity vocabulary.

## Fork & Install

### Repository setup

- Fork `obra/superpowers` to `btc/superpowers` (public).
- Local clone at `~/Projects/src/superpowers`. `origin` → `btc/superpowers`, `upstream` → `obra/superpowers`.
- Customizations land on a `burndown-reviews` branch. `main` tracks upstream cleanly so rebases stay tractable.
- Bump `package.json` version to `<upstream-version>-btc.<N>`, where `<upstream-version>` is whatever the latest rebased upstream version is and `<N>` increments per fork release. At the time this spec is being written, upstream is at `5.0.7`, so the first fork release is `5.0.7-btc.1`. After a future upstream rebase to (say) `5.1.0`, the first fork release on that base is `5.1.0-btc.1`.

### Marketplace repo

A separate small public repo, `btc/claude-plugins`, holds a single file: `.claude-plugin/marketplace.json` pointing the `superpowers` plugin at `btc/superpowers`.

### Install command

```text
/plugin marketplace add btc/claude-plugins
/plugin uninstall superpowers@claude-plugins-official
/plugin install superpowers@btc-plugins
```

The `btc-plugins` name is what the marketplace.json declares; the GitHub repo name is `btc/claude-plugins`.

### Sync with upstream

When `obra/superpowers` releases a new version:

1. On `main`: `git fetch upstream && git rebase upstream/main && git push --force-with-lease origin main`.
2. On `burndown-reviews`: `git rebase main`. Conflicts mostly land in the three edited skill files; the new files (`burndown-reviews/`, `burndown-reviewer.md`, `burndown-fixer.md`) are independent and don't conflict.

Rebase is preferred over merge: it keeps the divergence visible as a clean linear set of customization commits on top of upstream.

## Architecture

### High-level flow

Each existing skill keeps its current shape but gains one new step between "artifact written" and "user reviews":

```
brainstorming:               artifact written → self-review → BURNDOWN-REVIEWS → user review → writing-plans
writing-plans:               plan written     → self-review → BURNDOWN-REVIEWS → user review → subagent-driven-development
subagent-driven-development: impl complete    → tests pass  → BURNDOWN-REVIEWS → user review → done
```

The user only sees the final, post-burndown artifact at the user-review gate. Orchestrator-vs-reviewer disagreements (defined below) are surfaced inline during the loop, not deferred to the user-review gate.

### The loop (per checkpoint)

Pseudocode (illustrative; the actual loop lives in the skill prose):

```
for round in 1..7:
  # A. dispatch reviewers concurrently
  opus_findings, sonnet_findings = parallel(
    reviewer(model=opus,    artifact, predecessor, stage),
    reviewer(model=sonnet,  artifact, predecessor, stage),
  )
  # orchestrator stamps reviewer + round into finding IDs post-hoc:
  # the reviewer itself emits sequential IDs ("1", "2", ...) and the
  # orchestrator namespaces them as e.g. "opus-r3-2" / "sonnet-r3-1".
  all_findings = stamp(opus_findings, "opus", round) +
                 stamp(sonnet_findings, "sonnet", round)

  # B. orchestrator judges each finding
  fix_list, disagreements = [], []
  for f in all_findings:
    if orchestrator_agrees(f):
      fix_list.append(f)
    else:
      disagreements.append(f)   # orchestrator thinks reviewer is wrong

  # C. merge near-duplicate accepted findings (see Reconcile algorithm)
  fix_list = merge_duplicates(fix_list)

  # D. pause if orchestrator disagrees with any reviewer findings
  if disagreements:
    resolved = surface_to_user(disagreements)   # natural-language exchange
    fix_list += resolved.kept                   # any disagreements user wants applied

  # E. end early on clean review
  if fix_list is empty:
    return "clean"

  # F. dispatch fixer (rounds 1..7)
  dispatch_fixer(model=fixer_model_for_stage, artifact, fix_list)

# Round 8 — inventory pass: reviewers only, no judging, no fixer
final_opus, final_sonnet = parallel(
  reviewer(model=opus,   artifact, predecessor, stage),
  reviewer(model=sonnet, artifact, predecessor, stage),
)
return ("hard_escalate", final_opus + final_sonnet)
```

**Concurrency** is real parallelism: the orchestrator issues both reviewer Task tool calls in a single message so they run simultaneously.

**Statelessness:** reviewers and fixers are fresh subagents each round. They see the current artifact, not prior rounds. Rationale: an effective fix removes the issue from the artifact, so a stateless reviewer next round won't re-flag it. An ineffective fix leaves the issue in place, so it gets re-flagged — that recurrence is itself a useful "convergence failing" signal.

**Caveat to statelessness — re-fixing dropped findings.** If both reviewers flag the same finding round after round and the user once told the orchestrator "skip it," the orchestrator does not remember that decision across rounds. Next round, the orchestrator reads the same finding fresh, judges it, and (if it agrees with the reviewer) applies the fix — undoing the user's prior intent. The user's only safeguard is to say "skip" again when it re-surfaces. Two reasons we accept this: (i) reviewers are stateless and the prompt stays minimal; (ii) most real-world fixes change the artifact such that the reviewer no longer re-flags it. If a finding genuinely cannot be removed, the round-7 hard escalate ultimately exposes it.

**All findings fixed each round.** The fix list per round = orchestrator-accepted findings + user-resolved disagreements that the user wants kept. Nothing is deferred to a later round.

### Reconcile algorithm

Disagreement here means **orchestrator vs. reviewer**, not reviewer vs. reviewer. The orchestrator (main Claude) reads each finding from both reviewers and judges it independently. Solo findings (present in only one reviewer's report) are not treated specially — they're judged like any other finding. The orchestrator's judgment is the safeguard against bad reviewer output, and the user is only pulled in when the orchestrator and a reviewer disagree.

For each finding the orchestrator decides one of:

1. **Accept** — the finding is real and the suggested fix is sound. Goes into the fix list.
2. **Disagree** — the orchestrator thinks the reviewer is wrong: the issue isn't real, or the suggested fix is incorrect, or the reviewer misread the artifact. Goes into the disagreement list, surfaced to the user.

After judgment, the orchestrator merges near-duplicate accepted findings:

- Two accepted findings at the same `location` whose `suggested_fix` paragraphs describe the same intervention collapse to one entry. The merged entry takes the higher of the two severities and the more specific (or unioned) fix instruction.
- The severity adjacency rule for "same location, slightly different severity": **H↔M** are mergeable; **M↔L** are mergeable; **H↔L** are not (treat as separate findings, judge each independently). This rule is non-transitive — M does not bridge H and L.
- Conflicting fixes at the same location (one finding says "lock decision X", another says "defer decision X") cannot be merged. The orchestrator judges each finding independently — it may accept one and disagree with the other, or accept both as separate fix steps if they're complementary.

The orchestrator makes the "real issue?" / "fix sound?" / "same intervention?" judgments in prose. There is no string-similarity threshold or other mechanical rule; this is a reading-comprehension task and Claude is the right tool for it.

**Reconcile and unit-testing:** because the algorithm runs in the orchestrator's prose (not a callable function), it is not unit-testable in the conventional sense. Tests for reconcile take the form of **fixture-based orchestrator-simulation tests**: a harness feeds canned reviewer outputs into a scripted orchestrator run and asserts the resulting fix list and disagreement list. See Testing for harness details.

### Disagreement UX

When the orchestrator disagrees with one or more reviewer findings in a round, it pauses the loop and **talks the disagreements through with the user in plain language**, batched per round.

For each disagreement, the orchestrator:

1. States the reviewer's finding clearly (location, severity, claim, suggested fix).
2. Explains in its own words why it disagrees — what the reviewer might be missing, why the suggested fix is wrong, or why the artifact is fine as-is.
3. Offers a recommendation (usually "skip this finding") and asks for confirmation.
4. Listens to the user's response in whatever form it comes — "yeah skip it", "no, the reviewer is right, fix it", "neither — do this instead", a paragraph of nuance.
5. Restates what it heard before applying, so the user can correct.

No fixed verdict vocabulary. The orchestrator interprets natural-language responses and either drops the finding (skip) or adds it to the fix list (with optional user-authored fix text overriding the reviewer's suggestion).

**Edge case (high orchestrator-disagreement rate):** if the orchestrator finds itself disagreeing with many reviewer findings in a single round, that's a signal the reviewer prompt or rubric may be miscalibrated. The orchestrator flags it: "I'm disagreeing with N reviewer findings this round, which is unusual. Want me to keep going, or pause and look at the reviewer prompts?" The threshold is the orchestrator's judgment, not a fixed number — what matters is the deviation from the run's normal cadence.

**No silent defaults.** If the user's reply is ambiguous, the orchestrator asks again rather than guessing.

### Round-7 hard escalate

Rounds 1 through 7 are full review-judge-fix cycles. After round 7's fix completes, the orchestrator runs **round 8 as a reviewer-only inventory pass** — dispatch both reviewers concurrently, do not judge, do not fix. The combined residual finding list goes straight to the user:

> "7 rounds didn't converge. Here's what's still flagged. Accept as-is, run more rounds, or fix manually?"

The user can extend by N rounds, accept the current state, or take over.

### Failure modes

- **Reviewer subagent crashes or times out** → retry once. If still failing, abort the loop and surface to the user with a clear error.
- **Fixer subagent crashes or times out** → same.
- **Fixer claims success but the artifact's content is unchanged** — verified via content hash (e.g., sha256) before and after dispatch. mtime is unreliable as a signal across filesystems and tools and is not used. Treat as a fix failure, retry once, abort if still failing.
- **Intra-round fix conflicts** — when multiple findings touch overlapping content (e.g., two findings edit the same paragraph in incompatible ways), the fixer applies findings using its own judgment and returns the artifact in the best state it could achieve plus an explicit list of findings it was unable to apply cleanly. The orchestrator surfaces the skipped findings to the user as disagreements in the next round (since the fix didn't take, those findings will be re-raised by the reviewers anyway, but flagging them explicitly avoids silent partial application).

## Reviewer subagent

`agents/burndown-reviewer.md`. Single agent definition; the orchestrator dispatches with `model=opus` or `model=sonnet` at call time.

### Inputs (passed in dispatch prompt)

- `stage`: `spec` | `plan` | `impl`
- Path to the artifact under review.
- Predecessor context — a structured value whose shape varies by stage:
  - `spec` stage: a single path to a context file `<artifact_basename>.context.md` that the brainstorming skill writes alongside the spec before invoking burndown-reviews. Minimum content: the user's original request, the locked-in design decisions from the brainstorm, and any explicit non-goals.
  - `plan` stage: a single path to the spec the plan was derived from.
  - `impl` stage: an object `{ plan_path, diff_base, diff_paths }` where `plan_path` points to the implementation plan, `diff_base` is the git ref (commit SHA or branch name) recorded at the start of subagent-driven-development, and `diff_paths` is the explicit list of files the impl run is expected to have touched. The reviewer reads the diff between `diff_base` and `HEAD` restricted to `diff_paths`.

The reviewer subagent does not receive its own model name or round number — the orchestrator stamps those into finding IDs after receiving the reviewer's output (see Output format below).

### Role framing

"You are a critical reviewer of a `{stage}` artifact in a Superpowers-driven workflow. Your job is to find substantive issues that would prevent the artifact from doing its job. Be direct. Don't pad. Don't restate the artifact."

### Severity rubric

- **H** (high): blocks the artifact from being usable. Spec contradictions, missing critical info, scope drift that breaks the stated goal, code that fails tests or breaks the build.
- **M** (medium): substantive issue that should be fixed before moving on. Unclear requirement, missing error handling, gap in test coverage, ambiguous step in a plan.
- **L** (low): improvement, not blocking. Naming, minor reorganization, redundant content.
- **nit**: trivial polish. Typos, formatting, word choice.

### Per-stage focus (in dispatch prompt)

- *spec*: scope, contradictions, vague or unmeasurable requirements, missing constraints, testability, ambiguity that would let two implementers diverge.
- *plan*: each step's preconditions and postconditions, ordering and dependencies, scope match against the spec, over-engineering, missing decision points.
- *impl*: code matches plan, tests exist and pass, no regressions, follows project conventions, no scope creep, diff is minimal for what was asked.

### Output format

Hybrid: structured headers (machine-parseable for reconcile) + prose body (human-readable for escalation).

```
## Finding {n}
- severity: H | M | L | nit
- location: <location specifier — see below>
- claim: <1-3 sentences — what's wrong>
- suggested_fix: <1-3 sentences — what to do>
```

The reviewer emits sequential numeric IDs (`1`, `2`, `3`, ...). The orchestrator namespaces them post-hoc as `opus-r{round}-{n}` or `sonnet-r{round}-{n}`.

**Location specifier rules:**

- **Prose artifacts (spec, plan):** `<path> § "<section heading>"` — e.g., `spec.md § "Architecture"`. If the issue is sub-section, append a paragraph index: `spec.md § "Architecture" ¶3`.
- **Code artifacts (impl):** `<path>:L<start>-L<end>` — e.g., `src/loop.ts:L42-58`. Single-line issues: `src/loop.ts:L42`.
- **Either is acceptable for impl-stage prose docs** (e.g., README updates).

The reconcile orchestrator treats overlapping line ranges as the same location, and treats identical section headings as the same location. Paragraph indices distinguish issues within a section.

Empty list if clean. No preamble, no summary, no commentary outside findings.

## Fixer subagent

`agents/burndown-fixer.md`. Single agent definition; orchestrator picks the model per stage.

### Inputs

- Path to the artifact.
- The reconciled finding list (post-disagreement-resolution).
- `stage`.

### Role framing

"You are a fixer applying review findings to a `{stage}` artifact. Address every finding. Preserve unrelated content. Make minimal edits — fix what's flagged, nothing else."

### Stage-to-model mapping

- `spec` → `model=sonnet`
- `plan` → `model=sonnet`
- `impl` → `model=opus`

### Output

The updated artifact, written in place. A brief summary of what was changed.

## Integration points in existing skills

### `brainstorming/SKILL.md`

The current checklist has these items:
1. Explore project context
2. Offer visual companion (conditional)
3. Ask clarifying questions
4. Propose 2-3 approaches
5. Present design
6. Write design doc
7. Spec self-review
8. User reviews written spec
9. Transition to implementation

Insert burndown-reviews invocation between step 7 and step 8 as a new step "Burndown review pass". The existing self-review (step 7) stays — it's a quick inline check before kicking off the heavier subagent loop. Before step 6 (Write design doc), the brainstorming skill also writes the predecessor context file `<artifact_basename>.context.md` alongside the spec — this is what gets handed to burndown-reviews as the predecessor input.

### `writing-plans/SKILL.md`

Insert after the plan document is written and after any self-check step the skill currently performs, and **before** the user-review prompt and handoff to subagent-driven-development. The plan itself is the artifact; the spec is the predecessor.

The exact step number against the current skill file is confirmed during implementation, but the location is fixed: after "plan written" and before "user reviews plan / hand off to executor". An implementer reading the current skill file will find this seam unambiguously — there is one user-review prompt at the end of the skill, and burndown-reviews is inserted immediately above it.

### `subagent-driven-development/SKILL.md`

Insert after all implementation tasks complete and tests pass, and **before** the completion handoff to the user. The artifact is the working tree (changes since the implementation began); the predecessor is the plan plus the diff scope (see Reviewer subagent inputs).

Same as above: the exact step number is confirmed during implementation, but the seam is "after tests pass, before user-review/done." There is one such transition in the skill.

### Voice-tunable detection

The "skip the burndown for this one" voice tunable (see Configuration) is detected by the **parent skill** at its very start, before it begins producing the artifact. Each of `brainstorming`, `writing-plans`, and `subagent-driven-development` includes a step at its top that reads roughly: "Before continuing, check whether the user has expressed an intent to skip the burndown review for this run. If so, mark `burndown_skip = true` and proceed directly to the user-review gate when the artifact is written." The burndown-reviews skill itself is not responsible for skip detection — by the time it's invoked, the parent has already decided.

### What gets passed to `burndown-reviews` at each checkpoint

- `artifact_path` — the file (or working-tree scope) under review.
- `predecessor` — a structured value whose shape varies by stage; see Reviewer subagent § Inputs.
- `fixer_model` — `sonnet` for spec & plan; `opus` for impl. Overridable by user voice.
- `stage` — `spec` | `plan` | `impl`. Used in reviewer prompts to set context.

Reviewer dispatch is always Opus + Sonnet concurrently, regardless of stage. Only the fixer model varies.

## Configuration

### Hardcoded in the skill

- Reviewers: Opus + Sonnet, always concurrent.
- Round cap: 7.
- Severity vocabulary: H, M, L, nit.
- Stage-to-fixer mapping.

### Tunable by user voice

The orchestrator listens for these intents at the noted points:

- **"Skip the burndown for this one"** — detected by the parent skill (brainstorming / writing-plans / subagent-driven-development) at the start of its run, before it begins producing the artifact. If detected, the parent skill skips the burndown invocation and goes straight to the user-review gate when the artifact is written.
- **"Run more rounds"** — detected by burndown-reviews after a hard-escalate (round 8 inventory). The user specifies a number; the orchestrator continues from round 8 onward for that many additional rounds.
- **Override the fixer model** — at any point during a run, the user can specify a different fixer model than the stage default ("use Opus as fixer this time" for spec/plan stages; "use Sonnet as fixer this time" for impl stage; or any of the supported models). Symmetric — the override works in either direction.

No env vars, no `settings.json` keys, no flags.

## File layout in the fork

```
~/Projects/src/superpowers/   (fork on burndown-reviews branch)
├── skills/
│   ├── brainstorming/SKILL.md          # edited (insert burndown invocation)
│   ├── writing-plans/SKILL.md          # edited (insert burndown invocation)
│   ├── subagent-driven-development/SKILL.md  # edited (insert burndown invocation)
│   └── burndown-reviews/SKILL.md       # NEW
├── agents/
│   ├── code-reviewer.md                # unchanged (upstream)
│   ├── burndown-reviewer.md            # NEW
│   └── burndown-fixer.md               # NEW
├── tests/burndown-reviews/             # NEW
├── package.json                        # version bumped (see Fork & Install)
└── CHANGELOG.md                        # fork divergence entry

~/Projects/src/claude-plugins/          (separate marketplace repo, GH: btc/claude-plugins)
└── .claude-plugin/marketplace.json     # points superpowers at btc/superpowers
```

## Testing

Tests live under `tests/burndown-reviews/`, following the existing superpowers test harness conventions.

### Orchestrator-simulation (no real subagent calls; mocked reviewer/fixer outputs)

Reconcile and the loop run inside the skill's prose, not as a callable function — there is no module to unit-test directly. These tests instead drive a scripted orchestrator run with canned reviewer/fixer outputs and assert on the resulting fix list, disagreement list, and per-round transitions.

- Two reviewers produce identical findings at the same location with compatible fixes → fix list contains one merged entry.
- Two reviewers produce findings at the same location with conflicting fixes → orchestrator judges each independently; both can land in the fix list (as separate items) or one can be disagreed with.
- One reviewer produces a finding the other doesn't → orchestrator judges it as a regular finding (accept or disagree); not auto-classified as disagreement.
- Severity merge: H+M at same location → merged with severity H; M+L → merged with severity M; H+L → not merged, two separate findings.
- Round-7 boundary: round 7 fix runs, then round 8 inventory pass runs reviewers without judging or dispatching the fixer.
- Failure-mode tests:
  - Reviewer subagent fails on first call → orchestrator retries once → succeeds → loop continues.
  - Reviewer subagent fails twice → orchestrator aborts loop with clear error.
  - Fixer reports success but content hash unchanged → orchestrator retries once → second attempt's content hash unchanged → abort with clear error.
  - Fixer reports skipped findings (intra-round conflicts) → those findings surface as disagreements in the next round.

### Integration (real subagent dispatch, fixture artifacts; gated by default)

- End-to-end on a deliberately-flawed spec fixture: should converge in <7 rounds.
- End-to-end on a deliberately-clean spec fixture: should converge in round 1 (no findings).
- End-to-end on a fixture designed to be unsolvable (irreconcilable issue, e.g., reviewers disagree on a load-bearing decision): should hit round 7 and hard-escalate.

Integration tests are gated/skipped by default to avoid running expensive subagent calls in CI; they're explicitly runnable when changes touch the loop logic.

## Open questions for implementation

These are deliberately deferred to the implementation plan, not resolved here:

1. **Exact step number for the burndown invocation in `writing-plans/SKILL.md` and `subagent-driven-development/SKILL.md`.** The location is fixed (immediately before the user-review/handoff step at the end of each skill), but the literal step number depends on the current state of those files at the time the implementation plan is written. The plan should record the chosen number explicitly.
2. **Test harness specifics.** Fixture format, the orchestrator-simulation harness, and the gating mechanism for integration tests should match the conventions already in `tests/` — needs a read of that directory before the plan is written.
3. **Brainstorming context-file production point.** The brainstorming skill writes `<artifact_basename>.context.md` alongside the spec, but the exact step where that write happens (before step 6 "Write design doc"? as a sub-step? immediately before the burndown invocation?) is left to the plan to choose so it composes cleanly with the existing checklist.
