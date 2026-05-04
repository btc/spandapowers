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
- Bump `package.json` version to `5.0.7-btc.1` so the loaded version is unambiguous.

### Marketplace repo

A separate small public repo, `btc/claude-plugins`, holds a single file: `.claude-plugin/marketplace.json` pointing the `superpowers` plugin at `btc/superpowers`.

### Install command

```fish
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
writing-plans:               plan written     → self-review → BURNDOWN-REVIEWS → user review → executing-plans
subagent-driven-development: impl complete    → tests pass  → BURNDOWN-REVIEWS → user review → done
```

The user only sees the final, post-burndown artifact at the user-review gate. Disagreements between reviewers are surfaced inline during the loop, not deferred to the user-review gate.

### The loop (per checkpoint)

```
round = 1
loop:
  # A. dispatch reviewers concurrently in a single message
  opus_findings, sonnet_findings = parallel(
    reviewer(model=opus, artifact, predecessor, stage),
    reviewer(model=sonnet, artifact, predecessor, stage),
  )

  # B. reconcile in-process (orchestrator, not a subagent)
  agreed, disagreements = reconcile(opus_findings, sonnet_findings)

  # C. pause on disagreements, conversational resolution
  if disagreements:
    resolved = surface_to_user(disagreements)   # natural-language back-and-forth
    findings = agreed + resolved                # resolved entries may include user-authored fix text
  else:
    findings = agreed

  # D. end early on clean review
  if findings is empty:
    return "clean"

  # E. fix all findings this round
  dispatch_fixer(model=fixer_model_for_stage, artifact, findings)

  # F. round cap
  if round == 7:
    return "hard_escalate"
  round += 1
```

**Concurrency** is real parallelism: the orchestrator issues both reviewer Task tool calls in a single message so they run simultaneously.

**Statelessness:** reviewers and fixers are fresh subagents each round. They see the current artifact, not prior rounds. Rationale: an effective fix removes the issue from the artifact, so a stateless reviewer next round won't re-flag it. An ineffective fix leaves the issue in place, so it gets re-flagged — that recurrence is itself a useful "convergence failing" signal.

**Caveat to statelessness:** if a reviewer keeps flagging something the user has explicitly dropped (a solo-finding disagreement the user resolved as "skip"), the reviewer will surface it again next round because it's stateless. This is acceptable: the user just says "drop again" or "I told you to skip this." If it persists, the round-7 hard escalate exposes it. We do not pass a "previously dropped" list to the reviewer; the reviewer prompt stays minimal.

**All findings fixed each round.** The fix list per round = agreed findings + user-resolved disagreements. Nothing is deferred to a later round.

### Reconcile algorithm

Lives in the skill prose (executed by the orchestrator), not a subagent. Cheap enough to run in-process; not worth a Task call.

1. For each Opus finding and Sonnet finding, the structural keys are `location` and `severity`.
2. **Agreed:** two findings at the same `location` (same severity, or within one tier — H/M counted together, M/L counted together) where the orchestrator judges that the two `suggested_fix` paragraphs describe the same intervention. Collapse to one entry, preferring the more specific suggested_fix or merging them into a single instruction.
3. **Disagreement (conflicting fixes):** two findings at the same `location` whose `suggested_fix` paragraphs would produce contradictory changes (e.g., "lock decision X" vs. "explicitly defer decision X").
4. **Disagreement (solo finding):** a finding present in only one reviewer's report. The other reviewer might've missed it, or might've judged it fine — the orchestrator can't tell, so it's a disagreement.

The orchestrator (main Claude) makes the "same intervention?" / "contradictory?" judgment in prose. There is no string-similarity threshold or other mechanical rule; this is a reading-comprehension task and Claude is the right tool for it.

### Disagreement UX

When the reconciler produces a non-empty disagreement list, the orchestrator pauses the loop and **talks the disagreements through with the user in plain language**, batched per round.

For each disagreement, the orchestrator:

1. Reads both reviewers' positions on the contested item.
2. Summarizes the actual disagreement in its own words — what each reviewer is concerned about, where they diverge, what's at stake.
3. Offers a recommendation if it has one (and says so), otherwise just asks.
4. Listens to the user's response in whatever form it comes — yes/no, "go with opus", "skip it", "do it differently — say X instead", a paragraph of nuance.
5. Restates what it heard before applying, so the user can correct.

No fixed verdict vocabulary. No "pick A/B/custom" menu. The orchestrator interprets natural-language responses and constructs the fix instructions that get passed to the fixer subagent.

**Edge case (high disagreement count):** if a round produces an unmanageable batch (>5–7 disagreements), the orchestrator flags it explicitly: "we're seeing unusual disagreement this round — reviewers may be miscalibrated against each other. Want me to keep going, or pause and look at the reviewer prompts?"

**No silent defaults.** If the user's reply is ambiguous, the orchestrator asks again rather than guessing.

### Round-7 hard escalate

When round 7's fix completes, the orchestrator runs one final reviewer pair as a "round 8 inventory pass" — but skips the fix step. The residual finding list is surfaced to the user with: "7 rounds didn't converge. Here's what's still flagged. Accept as-is, run more rounds, or fix manually?"

The user can extend by N rounds, accept the current state, or take over.

### Failure modes

- Reviewer subagent crashes or times out → retry once. If still failing, abort the loop and surface to the user with a clear error.
- Fixer subagent crashes or times out → same.
- Fixer claims success but the artifact didn't actually change (file mtime unchanged, or content identical) → treat as a fix failure, retry once, abort if still failing.

## Reviewer subagent

`agents/burndown-reviewer.md`. Single agent definition; the orchestrator dispatches with `model=opus` or `model=sonnet` at call time.

### Inputs (passed in dispatch prompt)

- `stage`: `spec` | `plan` | `impl`
- Path to the artifact under review.
- Path to the predecessor artifact:
  - `spec` stage: the original user prompt / brainstorm transcript saved as a context file.
  - `plan` stage: the spec.
  - `impl` stage: the plan, plus a pointer to the working tree / diff scope.

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
## Finding {reviewer}-{round}-{n}
- severity: H | M | L | nit
- location: <file path> § "<section>"   (or :L42-58 for code)
- claim: <1-3 sentences — what's wrong>
- suggested_fix: <1-3 sentences — what to do>
```

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

Insert burndown-reviews invocation between step 7 and step 8 as a new step "Burndown review pass". The existing self-review (step 7) stays — it's a quick inline check before kicking off the heavier subagent loop.

### `writing-plans/SKILL.md`

Insert after the plan is written and self-checked, before handing off to executing-plans / subagent-driven-development. Exact insertion point to be confirmed against the current skill file during implementation.

### `subagent-driven-development/SKILL.md`

Insert after all implementation tasks complete and tests pass, before the completion handoff. Exact insertion point to be confirmed against the current skill file during implementation.

### What gets passed to `burndown-reviews` at each checkpoint

- `artifact_path` — the file under review.
- `predecessor_path` — what the artifact was derived from.
- `fixer_model` — `sonnet` for spec & plan; `opus` for impl.
- `stage` — `spec` | `plan` | `impl`. Used in reviewer prompts to set context.

Reviewer dispatch is always Opus + Sonnet concurrently, regardless of stage. Only the fixer model varies.

## Configuration

### Hardcoded in the skill

- Reviewers: Opus + Sonnet, always concurrent.
- Round cap: 7.
- Severity vocabulary: H, M, L, nit.
- Stage-to-fixer mapping.

### Tunable by user voice

The skill prose explicitly tells the orchestrator to listen for these phrasings before invoking burndown-reviews or during the loop:

- "Skip the burndown for this one" before invoking the parent skill → orchestrator goes straight to user-review.
- "Run more rounds" after a hard-escalate → orchestrator extends by N rounds the user specifies.
- "Use Opus as fixer this time" → orchestrator overrides the stage default.

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
├── package.json                        # bumped to 5.0.7-btc.1
└── CHANGELOG.md                        # fork divergence entry

~/Projects/src/btc-claude-plugins/      (separate marketplace repo)
└── .claude-plugin/marketplace.json     # points superpowers at btc/superpowers
```

## Testing

Tests live under `tests/burndown-reviews/`, following the existing superpowers test harness conventions.

### Unit (no real subagent calls; mocked reviewer outputs)

- Reconciler: identical-finding case → "agreed" with single collapsed entry.
- Reconciler: same-location-conflicting-fix case → "disagreement".
- Reconciler: solo-reviewer finding case → "disagreement".
- Round-7 boundary: triggers the hard-escalate inventory pass.

### Integration (real subagent dispatch, fixture artifacts; gated by default)

- End-to-end on a deliberately-flawed spec fixture: should converge in <7 rounds.
- End-to-end on a deliberately-clean spec fixture: should converge in 1 round.
- End-to-end on a fixture designed to be unsolvable (irreconcilable issue): should hit round 7 and hard-escalate.

Integration tests are gated/skipped by default to avoid running expensive subagent calls in CI; they're explicitly runnable when changes touch the loop logic.

## Open questions for implementation

These are deliberately deferred to the implementation plan, not resolved here:

1. **Exact prose insertion points in `writing-plans/SKILL.md` and `subagent-driven-development/SKILL.md`.** Both need to be read carefully during implementation to find the cleanest seam.
2. **How `predecessor_path` is constructed for the spec stage.** The original brainstorm transcript isn't a single file today; the simplest approach is to write a brief context file capturing the user's intent before invoking burndown-reviews.
3. **Test harness specifics.** The exact fixture format and how integration tests gate themselves matches what's already in `tests/`; needs a read of that directory before the plan is written.
