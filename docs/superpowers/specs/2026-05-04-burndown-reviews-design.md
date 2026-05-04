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
- Bump `package.json` version to `<upstream-version>+btc.<N>`, where `<upstream-version>` is whatever the latest rebased upstream version is and `<N>` increments per fork release. The `+btc.<N>` suffix is **semver build metadata** — it identifies the fork unambiguously without affecting semver precedence (build metadata is ignored when comparing versions, so the fork is not seen as "older" than upstream). At the time this spec is being written, upstream is at `5.0.7`, so the first fork release is `5.0.7+btc.1`. After a future upstream rebase to `5.1.0`, the first fork release on that base is `5.1.0+btc.1`.

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
deferred_findings = []   # carried over from prior round's fixer (intra-round conflicts)

for round in 1..7:
  # A. dispatch reviewers concurrently
  opus_findings, sonnet_findings = parallel(
    reviewer(model=opus,    artifact, predecessor, stage),
    reviewer(model=sonnet,  artifact, predecessor, stage),
  )
  # orchestrator stamps reviewer + round into finding IDs post-hoc:
  # the reviewer itself emits sequential IDs ("1", "2", ...) and the
  # orchestrator namespaces them as e.g. "opus-r3-2" / "sonnet-r3-1".
  # Deferred findings from the previous round join the judgment input.
  all_findings = stamp(opus_findings, "opus", round) +
                 stamp(sonnet_findings, "sonnet", round) +
                 deferred_findings

  # B. orchestrator judges each finding (3 outcomes: accept / override / escalate)
  fix_list, disagreements = [], []
  for f in all_findings:
    verdict = orchestrator_judgment(f)
    if verdict == "accept":
      fix_list.append(f)
    elif verdict == "override":
      pass   # confidently dropped, no user involvement
    elif verdict == "escalate":
      disagreements.append(f)   # genuinely uncertain — user decides

  # C. merge near-duplicate accepted findings (see Reconcile algorithm)
  fix_list = merge_duplicates(fix_list)
  disagreements = merge_duplicates(disagreements)   # same merge rules

  # D. pause if any escalated disagreements remain
  if disagreements:
    resolved = surface_to_user(disagreements)   # natural-language exchange
    fix_list += resolved.kept                   # entries user wants applied
                                                # (with optional user-authored fix text
                                                # overriding the reviewer's suggested_fix)

  # E. end early on clean review.
  # An empty fix_list here IS genuine clean: prior-round deferred findings were
  # folded into all_findings in step A and have already been routed to fix_list,
  # disagreements, or override by step B. If none survived (every finding was
  # accepted-and-merged-away, overridden, or escalated-and-user-skipped), there
  # is nothing to fix this round. "Clean" here means "no work remains," not
  # "reviewers found nothing" — user-skipped escalations count as cleared.
  if fix_list is empty:
    return "clean"

  # F. dispatch fixer. dispatch_fixer encapsulates the full Failure-modes state
  # machine: pre/post content-hash check, single retry on unchanged-with-empty-
  # deferred failure, the new-files report, and the fatal_abort path. It returns
  # either {deferred: [...]} (possibly empty) on success or signals fatal_abort.
  # The assignment REPLACES the prior round's deferred list — anything from
  # earlier rounds was already re-judged in step B above.
  fixer_result = dispatch_fixer(model=fixer_model_for_stage, artifact, fix_list)
  if fixer_result is fatal_abort:
    surface_error_and_exit()   # no round 8, no return value
  deferred_findings = fixer_result.deferred   # may be []; replaces prior value
  # deferred findings retain their original IDs (e.g., "opus-r2-3" stays
  # "opus-r2-3" when re-judged in round 3) so traceability is preserved

# Round 8 — inventory pass: reviewers only, no judging, no fixer.
# Reached only when the for-loop completes naturally (no early `return "clean"`,
# no fatal abort exit).
final_opus, final_sonnet = parallel(
  reviewer(model=opus,   artifact, predecessor, stage),
  reviewer(model=sonnet, artifact, predecessor, stage),
)
# Any non-empty deferred_findings carried in from round 7 are appended to the
# residual so the user sees them — they describe issues the fixer couldn't
# resolve and which may not be visible in the artifact text the round-8
# reviewers see.
residual = merge_duplicates(final_opus + final_sonnet + deferred_findings)
if residual is empty:
  return "clean"   # round 7's fixer happened to land it
return ("hard_escalate", residual)
```

**Concurrency** is real parallelism: the orchestrator issues both reviewer Task tool calls in a single message so they run simultaneously.

**Statelessness:** reviewers and fixers are fresh subagents each round. They see the current artifact, not prior rounds. Rationale: an effective fix removes the issue from the artifact, so a stateless reviewer next round won't re-flag it. An ineffective fix leaves the issue in place, so it gets re-flagged — that recurrence is itself a useful "convergence failing" signal.

**Caveat to statelessness — re-fixing dropped findings.** Neither user-skipped findings nor confidently-overridden findings are remembered across rounds. If reviewers re-flag the same underlying issue in a later round (under a fresh ID), the orchestrator judges it fresh and may accept it — undoing a prior round's user-skip or confident override. The user's safeguard against re-application of skipped findings is to say "skip" again when it re-surfaces; the orchestrator's safeguard against re-applying its own prior overrides is to apply the same judgment again (the same arguments that justified the override last round still apply this round). Two reasons we accept this design: (i) reviewers are stateless and the prompt stays minimal; (ii) most real-world fixes change the artifact such that the reviewer no longer re-flags it. If a finding genuinely cannot be removed, the round-7 hard escalate ultimately exposes it.

**All findings fixed each round.** The fix list per round = orchestrator-accepted findings + user-resolved disagreements that the user wants kept. Nothing is deferred to a later round.

### Reconcile algorithm

Disagreement here means **orchestrator vs. reviewer**, not reviewer vs. reviewer. The orchestrator (main Claude) reads each finding from both reviewers and judges it independently. Solo findings (present in only one reviewer's report) are not treated specially — they're judged like any other finding. The orchestrator's judgment is the safeguard against bad reviewer output, and the user is only pulled in when the orchestrator and a reviewer disagree.

For each finding the orchestrator decides one of:

1. **Accept** — the finding is real and the suggested fix is sound. Goes into the fix list.
2. **Override (confident)** — the orchestrator is certain the reviewer is wrong (verifiable misreading, factual error, fix that contradicts a locked design decision, etc.). The finding is dropped silently. The user is not pulled in.
3. **Escalate (uncertain)** — the orchestrator suspects the reviewer is wrong but cannot fully verify, or the call genuinely depends on user judgment. The finding goes into the disagreement list, surfaced to the user via the Disagreement UX flow.

Escalation is reserved for genuine orchestrator uncertainty. If the orchestrator can verify the reviewer's mistake by reading the artifact, the spec, or the locked decisions, it overrides confidently and moves on. The user's time is the scarce resource the orchestrator is protecting.

After judgment, the orchestrator merges near-duplicates. The same merge rules apply to **both** the accepted fix list and the disagreement list — only the matching criterion differs:

- **Fix list (accepted findings):** two findings at the same `location` whose `suggested_fix` paragraphs describe the same intervention collapse to one entry. The merged entry takes the higher of the two severities and the more specific (or unioned) fix instruction.
- **Disagreement list (escalated findings):** two findings at the same `location` whose `claim` paragraphs describe the same underlying issue collapse to one entry. Their `suggested_fix` paragraphs are presented to the user as alternatives — the user is the one choosing what to do, so contradictory fix text is informative rather than a problem.
- **Severity adjacency** (applies to both lists): **H↔M** are mergeable; **M↔L** are mergeable; **H↔L** are not (treat as separate entries). Non-transitive — M does not bridge H and L. Merged severity = max of the two.
- **Overlapping line ranges** (impl stage): when two code-stage findings have overlapping line ranges at the same path, the merged location is the **union** (smallest start, largest end).
- **ID survival on merge:** when a deferred finding (carrying an older round's ID, e.g., `opus-r2-3`) merges with a fresh finding (e.g., `sonnet-r3-1`), the merged entry retains the **older deferred ID** to preserve the traceability chain. When two fresh findings of the same round merge, the orchestrator picks either ID (no specific rule).
- Conflicting fixes at the same location in the **fix list** (one finding says "lock decision X", another says "defer decision X") cannot be merged into a single accepted entry. The orchestrator must pick one — accept one and override or escalate the other, or accept the spirit of both and rewrite the merged fix instruction in its own words to resolve the conflict before passing to the fixer. Two contradictory `suggested_fix` strings must never reach the fixer at the same location.

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

No fixed verdict vocabulary. The orchestrator interprets natural-language responses and either drops the finding (skip) or adds it to the fix list.

**User-override fix text.** When the user resolves a disagreement with their own fix instruction ("don't do what the reviewer said — do this instead"), the orchestrator replaces the reviewer's `suggested_fix` field with the user's text and leaves the rest of the finding (severity, location, claim) intact. The fixer subagent receives the user-overridden finding identically to a reviewer-authored one — it has no awareness that the suggestion came from the user.

**Disagreements are deduped before surfacing.** The orchestrator runs the same merge rules on the disagreement list as on the fix list (same location + compatible suggested_fix → collapse; H↔M and M↔L adjacent; severity = max). The user sees one entry per distinct issue, not two near-identical entries from each reviewer.

**Edge case (high escalation rate):** if the orchestrator finds itself escalating many findings in a single round, that's a signal the reviewer prompt or rubric may be miscalibrated, *or* that the orchestrator is being too cautious about overriding. The orchestrator flags it: "I'm escalating N reviewer findings this round, which is unusual. Want me to keep going, or pause and look at the reviewer prompts?" The threshold is the orchestrator's judgment, not a fixed number — what matters is the deviation from the run's normal cadence.

**No silent defaults.** If the user's reply is ambiguous, the orchestrator asks again rather than guessing. (Confident overrides without escalation are not "silent defaults" — they're explicit orchestrator decisions, distinct from guessing on user input.)

### Round-7 hard escalate

Rounds 1 through 7 are full review-judge-fix cycles. After round 7's fixer dispatch exits without a fatal abort (success, partial-with-deferrals, or unchanged-content-with-deferrals all qualify), the orchestrator runs **round 8 as a reviewer-only inventory pass** — dispatch both reviewers concurrently, do not judge, do not fix. The orchestrator then merges `final_opus + final_sonnet + carried_deferred_findings` using the same merge rules as in-loop rounds so the user sees one entry per distinct issue. **Deferred findings carried in from round 7 are appended to the residual** before merge — they describe issues the fixer couldn't resolve and may not be visible to the round-8 reviewers, so they need explicit surfacing rather than being silently dropped at the boundary. (A round-7 fixer that hits the abort path per the failure-mode rules — e.g., crashes twice or produces an unfixable empty-diff failure — skips round 8 and surfaces the abort error directly to the user.) The deduped residual finding list goes straight to the user:

> "7 rounds didn't converge. Here's what's still flagged. Accept as-is, run more rounds, or fix manually?"

The user can extend by N rounds, accept the current state, or take over.

**Extension semantics.** If the user says "run more rounds," the orchestrator continues with **full review-judge-fix cycles** (rounds 1–7 semantics, not inventory-only). Round numbering continues sequentially (round 9, round 10, ...). After the user-specified extension count is exhausted, the orchestrator runs another inventory pass — **identical mechanics to round 8: both reviewers concurrently, no judgment, no fixer dispatch** — and presents the residual to the user again. The user may extend again, accept, or take over. There is no upper bound on extensions — the user is in charge.

### Failure modes

- **Reviewer subagent crashes or times out** → retry once. If still failing, abort the loop and surface to the user with a clear error.
- **Fixer subagent crashes or times out** → same. A fatal fixer abort in **any** round (1–7) immediately exits the loop with the error surfaced to the user; remaining rounds and the round-8 inventory pass are skipped.
- **Fixer claims success but the artifact's content is unchanged** — verified via content hash (e.g., sha256) before and after dispatch. mtime is unreliable as a signal across filesystems and tools and is not used.
  - For prose artifacts (spec, plan): the hash is over the artifact file's full bytes.
  - For code artifacts (impl): the hash is over the **concatenated full contents of the files in `diff_paths`** (sorted by path), not over git-diff output. This catches reverts-to-base (which would produce an empty diff before and after) and avoids false positives from unrelated git operations.
  - **Unchanged content + non-empty deferred list = legitimate** (the fixer determined it could apply none of the findings cleanly; that's the intended use of the deferred-findings exit). The orchestrator **does not retry** in this case — it advances directly to round N+1 with the deferred findings carried into the next round's judgment step. Consecutive unchanged-content-with-deferrals rounds are tolerated (no special early-abort condition); they resolve naturally via round-8 hard escalate. **Unchanged content + empty deferred list + non-empty fix list = failure.** In the failure case, retry once, abort if still failing.
  - **New files** (impl stage): if the fixer creates a new file outside `diff_paths` to address a finding (e.g., a missing test file), the fixer reports the new path explicitly in its return value. The unchanged-content failure check is **skipped for any round in which the fixer reports newly-created paths** — the new-file report is itself authoritative evidence that the fixer did work, so the hash equality (which would still hold over the original `diff_paths` since the hash never sees the new file pre-fixer) is not a failure signal. The orchestrator then extends its in-loop copy of `diff_paths` to include the new paths before the next round, so subsequent reviewer dispatches and subsequent hash checks both cover the expanded set.
  - **`diff_paths` ownership and lifetime.** The burndown-reviews orchestrator maintains its own mutable copy of `diff_paths` for the duration of the loop (extensions included). Newly-added paths persist for all subsequent rounds within the loop. SDD's originally-recorded value is **not altered** — when the loop exits, that record is unchanged.
- **Intra-round fix conflicts → deferred findings.** When multiple accepted findings touch overlapping content (e.g., two findings edit the same paragraph in incompatible ways), the fixer applies what it can using its own judgment and returns the artifact in the best state it could achieve plus an explicit list of findings it was unable to apply — the **deferred findings** for this round. The orchestrator passes the deferred list to the next round so the next round's judgment step sees them alongside the new reviewer output. Deferred findings retain their original IDs (a finding stamped `opus-r2-3` keeps that ID when judged again in round 3). **This is the sole exception to the "all findings fixed each round" rule** — deferred findings are by definition findings the fixer could not apply, not findings the orchestrator chose to defer. User-resolved "keep" findings (escalated disagreements the user said to apply) enter the fix list and are subject to the same deferral rules as reviewer findings; user-resolved "skip" findings are dropped from this round and not re-reviewed (reviewers may re-flag them next round per the statelessness caveat).
- **Override of a previously-deferred finding.** When a deferred finding from a prior round is judged again in the current round and the orchestrator picks the **override** verdict (rather than accept or escalate), the finding is dropped silently with the same semantics as overriding a fresh reviewer finding. The ID is retired. This is intentional: the deferred-list mechanism preserves traceability, but the orchestrator retains full authority to decide a previously-deferred issue is no longer worth pursuing.
- **Retries are sub-steps within a round.** A reviewer or fixer retry does not consume a round slot; the round counter only advances when the round completes (or returns clean / hard_escalate).

## Reviewer subagent

`agents/burndown-reviewer.md`. Single agent definition; the orchestrator dispatches with `model=opus` or `model=sonnet` at call time.

### Inputs (passed in dispatch prompt)

- `stage`: `spec` | `plan` | `impl`
- Path to the artifact under review.
- Predecessor context — a structured value whose shape varies by stage:
  - `spec` stage: a single path to a context file `<artifact_basename>.context.md` that the brainstorming skill writes alongside the spec before invoking burndown-reviews. Best-effort content: the user's original request, locked-in design decisions, and explicit non-goals — sections may be empty if the brainstorm didn't produce that material.
  - `plan` stage: a single path to the spec the plan was derived from.
  - `impl` stage: an object `{ plan_path, diff_base, diff_paths }` where `plan_path` points to the implementation plan, `diff_base` is a **commit SHA** (not a branch name) captured by the `subagent-driven-development` orchestrator in its own process **before any Task tool call is issued** — including parallel-dispatch messages — and `diff_paths` is the explicit list of files the impl run is expected to have touched. The reviewer reads the diff between `diff_base` and `HEAD` restricted to `diff_paths`. SDD passes the recorded SHA verbatim to burndown-reviews — by the time the burndown runs, the working tree may have advanced, but `diff_base` stays anchored to the pre-impl state.

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

- **Prose artifacts (spec, plan):** `<path> § "<H2>" / "<H3>" / ...` — the **full heading chain** from the H2 down to the section containing the issue. Examples: `spec.md § "Architecture" / "Failure modes"` (two-level), `spec.md § "Reviewer subagent" / "Inputs"` (two-level), `spec.md § "Architecture" / "The loop" ¶3` (two-level + paragraph index). Top-level sections use a single heading: `spec.md § "Architecture"`. The chain disambiguates section names that recur under different parents.
- **Code artifacts (impl):** `<path>:L<start>-L<end>` — e.g., `src/loop.ts:L42-58`. Single-line issues: `src/loop.ts:L42`.
- **Either is acceptable for impl-stage prose docs** (e.g., README updates).

The reconcile orchestrator treats overlapping line ranges as the same location, and treats identical full heading chains as the same location. Paragraph indices distinguish issues within a section.

Empty list if clean. No preamble, no summary, no commentary outside findings.

## Fixer subagent

`agents/burndown-fixer.md`. Single agent definition; orchestrator picks the model per stage.

### Inputs

- Path to the artifact.
- The reconciled finding list (post-disagreement-resolution).
- `stage`.
- For `impl` stage only: `diff_paths` (the in-scope file list) and `diff_base` (commit SHA). The fixer must not modify files outside `diff_paths` except by creating new files (which it then reports — see Output below). `diff_base` is informational; the fixer uses it to understand what's in scope vs. what was already in the tree before the impl run.

### Role framing

"You are a fixer applying review findings to a `{stage}` artifact. Address every finding. Preserve unrelated content. Make minimal edits — fix what's flagged, nothing else."

### Stage-to-model mapping

- `spec` → `model=sonnet`
- `plan` → `model=sonnet`
- `impl` → `model=opus`

### Output

A structured return value:

- The updated artifact, written in place.
- `deferred`: a list of finding IDs the fixer was unable to apply (intra-round conflicts; possibly empty). The orchestrator uses this list verbatim — IDs are preserved from the input fix list. See Failure modes § "Intra-round fix conflicts → deferred findings."
- `created_paths` (impl stage): a list of any new file paths the fixer created outside the input `diff_paths` (possibly empty). The orchestrator extends its in-loop `diff_paths` copy with these and exempts the round from the unchanged-content failure check.
- A brief summary of what was changed (human-readable; for the orchestrator's logs).

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

Insert burndown-reviews invocation between step 7 and step 8 as a new step "Burndown review pass". The existing self-review (step 7) stays — it's a quick inline check before kicking off the heavier subagent loop.

**Predecessor context file.** As part of the new burndown step (between 7 and 8), and before the burndown-reviews invocation itself, the brainstorming skill writes `<artifact_basename>.context.md` alongside the spec. This file is a best-effort summary of state already in the orchestrator's hand at this point in the brainstorm: the user's original request, any locked-in design decisions captured during the conversation, and any explicit non-goals. Sections may be empty if the brainstorm did not produce that content — the brainstorming skill does not synthesize material that wasn't discussed. The file's purpose is to give downstream reviewers the same context the spec author had, no more.

### `writing-plans/SKILL.md`

Insert after the plan document is written and after any self-check step the skill currently performs, and **before** the user-review prompt and handoff to subagent-driven-development. The plan itself is the artifact; the spec is the predecessor. (Exact step number: see Open question 1.)

### `subagent-driven-development/SKILL.md`

Insert after all implementation tasks complete and tests pass, and **before** the completion handoff to the user. The artifact is the working tree (changes since the implementation began); the predecessor is the plan plus the diff scope (see Reviewer subagent inputs). (Exact step number: see Open question 1.)

### Voice-tunable detection

The "skip the burndown for this one" voice tunable (see Configuration) is detected by the **parent skill** at two points: (i) at its very start, before it begins producing the artifact, and (ii) immediately before the burndown-reviews invocation. The two-point check handles the multi-turn nature of these skills (especially brainstorming): a user who decides mid-conversation to skip the burndown shouldn't have to restart. The most recent expressed intent wins.

Each of `brainstorming`, `writing-plans`, and `subagent-driven-development` includes (i) a step near the top that reads roughly: "Before continuing, check whether the user has expressed an intent to skip the burndown review for this run. If so, mark `burndown_skip = true`," and (ii) a re-check immediately before the burndown invocation that updates `burndown_skip` based on anything the user has said since. If `burndown_skip` is true at the invocation point, the skill proceeds directly to the user-review gate. The burndown-reviews skill itself is not responsible for skip detection — by the time it's invoked, the parent has already decided.

### What gets passed to `burndown-reviews` at each checkpoint

- `artifact_path` — the file (or working-tree scope) under review.
- `predecessor` — a structured value whose shape varies by stage:
  - `spec` stage: a path to `<artifact_basename>.context.md`.
  - `plan` stage: a path to the spec.
  - `impl` stage: an object `{ plan_path, diff_base, diff_paths }` populated by SDD itself (see Reviewer subagent § Inputs).
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
- **"Run more rounds"** — detected by burndown-reviews after a hard-escalate (round 8 inventory). The user specifies a number; the orchestrator continues from round 9 onward for that many additional full review-judge-fix cycles.
- **Override the fixer model** — detected by burndown-reviews at the start of round 1, on each disagreement-pause, and during the round-8 hard-escalate user exchange (so the user can re-tune mid-extension without restarting). **Last-write semantics**: the most recently stated override applies to all subsequent rounds; the user may change their mind mid-loop and the new value takes effect immediately. The user can specify any supported model ("use Opus as fixer this time" for spec/plan stages; "use Sonnet as fixer this time" for impl stage). Symmetric — the override works in either direction.

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
  - Reviewer subagent fails on first call → orchestrator retries once (within the same round) → succeeds → loop continues.
  - Reviewer subagent fails twice → orchestrator aborts loop with clear error.
  - Fixer reports success but content hash unchanged → orchestrator retries once → second attempt's content hash unchanged → abort with clear error.
  - Fixer reports deferred findings (intra-round conflicts) → those findings join the next round's judgment step alongside fresh reviewer output.
  - Extension after hard escalate: user requests N additional rounds → orchestrator runs full review-judge-fix cycles for rounds 9 through 8+N → another inventory pass at the end.
  - Confident override: orchestrator drops a reviewer finding without escalation when it can verify the finding is wrong against the spec or locked decisions.

### Integration (real subagent dispatch, fixture artifacts; gated by default)

- End-to-end on a deliberately-flawed spec fixture: should converge in <7 rounds.
- End-to-end on a deliberately-clean spec fixture: should converge in round 1 (no findings).
- End-to-end on a fixture designed to be unsolvable (irreconcilable issue, e.g., reviewers disagree on a load-bearing decision): should hit round 7 and hard-escalate.

Integration tests are gated/skipped by default to avoid running expensive subagent calls in CI; they're explicitly runnable when changes touch the loop logic.

## Open questions for implementation

These are deliberately deferred to the implementation plan, not resolved here:

1. **Exact step number for the burndown invocation in `writing-plans/SKILL.md` and `subagent-driven-development/SKILL.md`.** The location is fixed (immediately before the user-review/handoff step at the end of each skill), but the literal step number depends on the current state of those files at the time the implementation plan is written. The plan should record the chosen number explicitly.
2. **Test harness specifics.** Fixture format, the orchestrator-simulation harness, and the gating mechanism for integration tests should match the conventions already in `tests/` — needs a read of that directory before the plan is written.
