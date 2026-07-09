# Fable Model Swap — Design

**Date:** 2026-06-10
**Status:** Design approved in brainstorming; spec pending user review

## Problem

Claude Fable 5 (`claude-fable-5`) is now the most capable available model, and Claude Code supports the `fable` model slug natively as of 2.1.170 — including in the Task tool's `model` parameter (enum is now `["sonnet","opus","haiku","fable"]`). The spandapowers skills still pin their subagent dispatches to the previous tiering: Opus where the best model is wanted, Sonnet as the second reviewer model in diversity pairs.

## Goal

Shift every live Opus/Sonnet reference up one tier (with one exception: a model-specific behavioral prediction is dropped rather than swapped — see Changes):

- where **Opus** is used today → use **Fable** (`model="fable"`)
- where **Sonnet** is used today → use **Opus** (`model="opus"`)

The burndown-reviews reviewer pair changes from Opus + Sonnet to **Fable + Opus** (the pair the original request phrased as "Opus and Fable", ordered best-model-first per the files' existing convention). The cross-model review-diversity rationale is preserved — the pair stays two distinct models; only the tiers shift.

## Environment facts (verified empirically, 2026-06-10)

- Active Claude Code is 2.1.170; a live Task dispatch with `model="fable"` succeeded.
- `fable` support was verified present on 2.1.170 and absent on 2.1.153: on 2.1.153 the Task tool's model enum is `["sonnet","opus","haiku"]`, a `model="fable"` dispatch fails with `InputValidationError` before any agent spawns, and the `fable` CLI alias does not exist (only the full ID `claude-fable-5` works there). Builds 2.1.154–2.1.169 were not inspected — the exact build that introduced `fable` support was not pinned down; 2.1.170 is the verified-safe floor.
- *Spike context, not load-bearing:* agent frontmatter `model:` was observed to be a free string (not enum-validated) in the build inspected (2.1.153, confirmed against that build's bundled schema; not re-checked on 2.1.170). Nothing in this design depends on it — both agents touched by this design (`burndown-reviewer`, `burndown-fixer`) use `model: inherit`, which stays unchanged, so frontmatter validation behavior is irrelevant here.

**Compatibility requirement:** the updated skills require Claude Code ≥ 2.1.170 at dispatch time. On builds without `fable` support, dispatches that pass `model="fable"` fail loudly at validation (verified on 2.1.153 — no silent wrong-model fallback); 2.1.170 is the verified-safe floor.

## Changes (live content only)

Mapping applied: `opus` → `fable`, `sonnet` → `opus`. All line numbers cited in this section are pre-edit — insertions specified here shift them during implementation.

### `skills/burndown-reviews/SKILL.md`

- Frontmatter description: "Drives Opus + Sonnet reviewers" → "Drives Fable + Opus reviewers".
- Step A reviewer dispatch: one Task call with `model="fable"`, one with `model="opus"` (these exact strings).
- Finding ID stamps: `fable-r{round}-{n}` / `opus-r{round}-{n}` everywhere they appear, including the round-8 / post-extension inventory examples (`fable-r8-{n}` / `opus-r8-{n}`, `fable-r{N}-{n}` / `opus-r{N}-{n}`); the round-8 line's "(e.g., `r18` after 10 extension rounds concluding at round 18)" example parenthetical is unchanged — it contains no model name.
- `fixer_model`: always `fable` for all stages, at **all three** sites in the file where the always-opus constant appears:
  - line 21, inputs prose: "`fixer_model` — always `opus` for all stages … no code path may set it to anything other than `opus`" — both backticked names become `fable`;
  - line 37, pseudocode: `fixer_model_for_stage = opus` → `= fable` (note the spaces — a `fixer_model=opus` grep does not match this site);
  - line 59, step F dispatch parenthetical: "(always `opus`)" → "(always `fable`)".

  Still a fixed symbolic constant, still not tunable; the prose forbidding other values now names `fable`.
- The deliberate carve-out prose in step A is reworded for the new pair: the intentional cross-model diversity pairing is now `fable`+`opus`, and the "only *always-on* reviewer-pair Sonnet usage" sentence becomes, verbatim: "This is the only *always-on* reviewer-pair Opus usage and it stays (the #2/#3 escalated review panels are a separate, gated carve-out)." The panel-exclusion parenthetical is load-bearing and must be preserved — post-swap, Opus appears in both the always-on pair and the escalated panels, and this sentence covers only the former.
- Round-8 final-pass merge: rename the merge variables `final_opus + final_sonnet` → `final_fable + final_opus`. This intentionally diverges from the pseudocode variable names in the 2026-05-04 burndown spec, even though the skill's steps are otherwise "labeled to match" that spec's pseudocode. The rename creates a same-name/different-referent collision: post-swap, `final_opus` in the live skill names the *second* reviewer (the ex-Sonnet slot), while the old spec's pseudocode uses `final_opus` for the *first* reviewer — and the skill defers to that spec "for the why and the edge cases", of which the round-8 merge is one. Correspondence map (spec-side only — putting it in the skill text would reintroduce a `sonnet` token and break the Sonnet-gone check below): 2026-05-04-spec pseudocode `final_opus` (first reviewer) → live-skill `final_fable`; spec `final_sonnet` (second reviewer) → live-skill `final_opus`.
- Authority paragraph (§ "Spec"): amend with a one-line precedence note — "model names in the 2026-05-04 spec predate the 2026-06-10 Fable swap (see `docs/superpowers/specs/2026-06-10-fable-model-swap-design.md`); this skill file is authoritative for model selection (reviewer pair, fixer model, and any model-override behavior), including where the spec's pseudocode and dispatch table say otherwise." The path reference gives a reader who follows the skill's pointer into the old spec's pseudocode a route to this spec's `final_opus`/`final_fable` correspondence map; the filename adds a second `fable` match to an already-counted inventory line and contains no `sonnet`/`opus` token, so no grep check shifts. The note deliberately covers model selection generally, not just model *names*: the old spec contradicts the post-swap skill in its pseudocode, its stage dispatch table (`model=opus`), and its user-voice fixer-override feature (see Out of scope), and the note must trump all three. The historical spec itself stays unmodified.
- Step A dispatch instruction gains a one-line version-floor note: "the `fable` model slug requires Claude Code ≥ 2.1.170 (verified floor); builds without `fable` support fail loudly at dispatch validation." (Worded by capability, not build age — builds 2.1.154–2.1.169 were never inspected, so "older builds fail" would over-claim; see Environment facts.) (Verification provenance — verified-safe floor, fail-loudly confirmed on 2.1.153 — stays spec-side in Environment facts above; the skill note carries only the actionable statement.) The placement is deliberate: the note lives only at this burndown step-A dispatch site — the highest-traffic dispatch path — while the spec-level Compatibility requirement above covers all `model="fable"` dispatch sites (the burndown step-F fixer dispatch, SDD subagents, the escalation panels, the research-spike delegate); duplicating the note at every site is not worth the clutter.

### Burndown call sites (three files)

`skills/brainstorming/SKILL.md` (checklist step 8.3), `skills/writing-plans/SKILL.md` (burndown invocation), `skills/subagent-driven-development/SKILL.md` (impl-stage invocation): `fixer_model=opus` → `fixer_model=fable`. (These are three of the four live `fixer_model=opus` sites; the fourth is the test prompt in `tests/burndown-reviews/MANUAL-VERIFICATION.md`, handled in its own section below.)

### `skills/subagent-driven-development/SKILL.md`

- "All SDD subagents run **Opus**" → "**Fable**" (implementer, spec-compliance reviewer, code-quality reviewer, final reviewer). The adjacent line 105 ("the lever is not a bigger model (there isn't one) …") makes the same no-bigger-model claim as line 119's swapped text ("no more capable model than Fable") but names no model, so it needs no edit and stays true under Fable — intentionally unchanged.
- Escalation guidance: "re-dispatch (still Opus)" → "(still Fable)"; "there is no more capable model than Opus" → "than Fable".
- Final whole-implementation review escalation panel: "**Opus + Sonnet** — review-diversity carve-out" → "**Fable + Opus**". Implementer note (covers this panel and the `code-reviewer.md` panel below): the Fable + Opus escalation panels are intentional cross-model review diversity — two distinct models, not a capability ranking — so Opus's presence beside the "no more capable model than Fable" statement is deliberate; do not "consistency-fix" it away. The live lines already carry the "review-diversity carve-out" label, so this is spec-side guidance only — no additional skill-text change.

### `skills/requesting-code-review/code-reviewer.md`

Escalation panel: "**Opus + Sonnet** — a deliberate review-diversity carve-out, the only non-Opus model permitted here" → "**Fable + Opus** — … the only non-Fable model permitted here".

### `skills/delegating-research-spikes/`

- `SKILL.md`: delegate dispatches on model **fable** (was **opus**).
- `delegate-prompt.md`: "You run on model `opus`" → "You run on model `fable`".

### `agents/`

- `burndown-reviewer.md` description: "Dispatched concurrently as both Opus and Sonnet" → "as both Fable and Opus".
- `burndown-fixer.md` description: "dispatches it with Opus for all stages (the fixer model is always Opus and is not tunable)" → Fable.
- Frontmatter `model: inherit` stays unchanged in both.

### `tests/burndown-reviews/MANUAL-VERIFICATION.md`

- Test prompt: `fixer_model=opus` → `fixer_model=fable`.
- The behavioral prediction "(likely Sonnet, since Opus tends to respect locked decisions more aggressively)" describes the old pair; mechanically swapping the names would fabricate an unverified claim about Fable's behavior. Instead the model-specific parenthetical is dropped: "A reviewer will probably flag the denormalization as an anti-pattern."

## Out of scope

Historical artifacts keep their original model names — they record what was true when written:

- past specs and plans under `docs/` (including `docs/plans/` and `docs/superpowers/`)
- `RELEASE-NOTES.md` (no rewrite of old entries; no new entry — per scope decision, live content only)
- `skills/delegating-research-spikes/test-scenarios.md` (transcripts of past test runs)
- `skills/writing-skills/anthropic-best-practices.md` (quoted Anthropic guidance about Haiku/Sonnet/Opus)
- `tests/explicit-skill-requests/*.sh` Haiku test harnesses (test infrastructure, not dispatched skill content; the mapping does not touch Haiku)

The 2026-05-04 burndown spec stays unmodified; the precedence note added to the live skill (see Changes above) resolves the model-selection contradictions between the skill and that spec. That spec also specifies a complete user-voice fixer-override feature — last-write semantics, three detection points (start of round 1, each disagreement-pause, the round-8 hard-escalate exchange), and "the user can override to Sonnet (or any supported model)" — which the live skill already overrides (`fixer_model` is not a tunable parameter). That divergence is pre-existing and explicitly out of scope for this change; the broadened precedence note (see Changes) covers it.

## Verification

1. Mechanical greps over `skills/ agents/ tests/`:
   - **Pre-edit baseline (measured 2026-06-10 in the worktree, before any skill edits):** `grep -rni '\bopus\b' skills/ agents/ tests/ | wc -l` → 28; `grep -rni 'sonnet' skills/ agents/ tests/ | wc -l` → 13; `grep -rn 'fixer_model=opus' skills/ agents/ tests/ | wc -l` → 4. The post-change assertions below are meaningful only relative to this baseline — verify the deltas, not just the post-counts. All baselines in this section, whether dated 2026-06-10 or 2026-06-11, were measured against the same pre-edit worktree state (spec commit `7574d2a`; `skills/`, `agents/`, and `tests/` untouched).
   - **Sonnet gone:** `grep -rni 'sonnet' skills/ agents/ tests/` (no word boundaries, so identifier sites like `final_sonnet` are caught too) returns hits only in the out-of-scope historical files above — expected exactly: `skills/delegating-research-spikes/test-scenarios.md` 3 lines, `skills/writing-skills/anthropic-best-practices.md` 2 lines; total 5 matching lines, down from the 13-line baseline (measured 2026-06-10, same worktree as the other baselines). `MANUAL-VERIFICATION.md`'s sole Sonnet hit is removed by the parenthetical-drop change, so its absence from this list is by design.
   - **Surviving-opus invariant:** `grep -rni '\bopus\b' skills/ agents/ tests/` returns exactly the following hits — any hit not on this list is a missed swap. Line counts assume the existing line structure is preserved (edits replace text in place; no reflowing); if lines are split, verify by match sites instead:
     - `skills/burndown-reviews/SKILL.md` — 3 lines: the frontmatter description ("Drives Fable + Opus reviewers"); the step-A dispatch line (the `model="opus"` dispatch string, the `opus-r{round}-{n}` stamp, the `fable`+`opus` carve-out pairing, and the "only *always-on* reviewer-pair Opus usage" sentence — multiple matches on one line); the round-8/post-extension inventory line (`opus-r8-{n}`, `opus-r{N}-{n}` stamps). (The renamed merge variable `final_opus` does *not* match: `_` is a word character, so `\bopus\b` has no boundary there.)
     - `skills/subagent-driven-development/SKILL.md` — 1 line: the final-review escalation panel ("**Fable + Opus** — review-diversity carve-out").
     - `skills/requesting-code-review/code-reviewer.md` — 1 line: the escalation panel ("**Fable + Opus** … the only non-Fable model permitted here").
     - `agents/burndown-reviewer.md` — 1 line: the description ("Dispatched concurrently as both Fable and Opus").
     - Out-of-scope historical files: `skills/delegating-research-spikes/test-scenarios.md` — 5 lines (dispatch-on-opus transcript records); `skills/writing-skills/anthropic-best-practices.md` — 3 lines (quoted Anthropic guidance).
     - Expected total: 14 matching lines across 6 files, and nothing else. In particular `agents/burndown-fixer.md` drops out entirely (both of its Opus mentions become Fable), as do `tests/` (zero hits) and every other `skills/` file.
   - **Stale patterns return zero live hits:** `fixer_model=opus`, `fixer_model_for_stage = opus` (the spaced pseudocode form, not caught by the previous pattern), "(always \`opus\`)", "still Opus", "than Opus", "run on model \`opus\`", "model \*\*opus\*\*" (the delegating-research-spikes SKILL.md form), "run \*\*Opus\*\*". These patterns are written for `grep`'s basic regex (hence the escaped asterisks); with any other tool or regex flavor, prefer fixed-string matching — `grep -F` with the unescaped literals (`model **opus**`, `run **Opus**`) is equivalent and safer than re-escaping. Per-pattern pre-edit baselines (verified by grep in the worktree, 2026-06-11): `fixer_model=opus` → 4 sites (the four enumerated in Changes); every other listed pattern → exactly 1 site. Confirm each pattern reproduces its baseline pre-edit before trusting its post-edit zero — without that, a mistyped pattern returning zero is indistinguishable from a fixed site. Coverage caveat: "(always \`opus\`)" matches only the step-F dispatch site (pre-edit line 59) — the line-21 inputs prose reads "always \`opus\`" *without* parentheses (the unparenthesized literal matches both lines 21 and 59) — so line 21's swap is asserted by the surviving-opus invariant above (whose expected burndown-SKILL.md lines exclude the inputs prose), not by this pattern.
   - **Repo-wide scope check (nothing outside the three dirs):** from the repo root, `grep -rniE '\bopus\b|sonnet' . --exclude-dir=.git --exclude-dir=docs` must return hits only in `RELEASE-NOTES.md` (1 line — a historical entry, out of scope) plus files already enumerated by the Sonnet-gone and surviving-opus checks above. Post-change that is exactly 7 files: the 6 surviving-opus files plus `RELEASE-NOTES.md` (the 2 Sonnet-historical files are among the 6). Any hit in any other file is a live model reference the three-dir scoped greps would miss. Pre-edit baseline (verified 2026-06-11, same worktree): the same grep hits exactly 13 files — `RELEASE-NOTES.md` plus 12 files under `skills/ agents/ tests/` — confirming `commands/`, `hooks/`, `scripts/`, `README.md`, and all other root content carry no model references.
   - **Positive check (exhaustive fable inventory):** post-change, `grep -rni '\bfable\b' skills/ agents/ tests/` (pre-edit baseline: 0 hits) returns exactly the following — any expected site missing is a missed swap; any extra hit is scope creep. Same line-structure assumption as the surviving-opus invariant (in-place edits, no reflowing; the two additive burndown notes are each assumed to land as their own line — if either is appended to an existing matching line, counts shift by one); if in doubt, verify by match sites instead:
     - `skills/burndown-reviews/SKILL.md` — 8 lines: the frontmatter description ("Drives Fable + Opus reviewers"); the line-21 fixer-constant inputs prose (two backticked `fable` names); the line-37 pseudocode (`fixer_model_for_stage = fable`); the step-A dispatch line (`model="fable"` dispatch string, `fable-r{round}-{n}` stamp, `fable`+`opus` carve-out pairing — multiple matches on one line); the step-A version-floor note (backticked `fable` slug); the line-59 step-F parenthetical ("always `fable`"); the round-8/post-extension inventory line (`fable-r8-{n}`, `fable-r{N}-{n}` stamps); the § "Spec" precedence note ("Fable swap"). (The renamed merge variable `final_fable` does *not* match — `_` is a word character, same caveat as `final_opus` above.)
     - `skills/brainstorming/SKILL.md` — 1 line: checklist step 8.3 (`fixer_model=fable`).
     - `skills/writing-plans/SKILL.md` — 1 line: the burndown invocation (`fixer_model=fable`).
     - `skills/subagent-driven-development/SKILL.md` — 5 lines: "All SDD subagents run **Fable**"; "re-dispatch (still Fable)"; "no more capable model than Fable"; the final-review escalation panel ("**Fable + Opus**"); the impl-stage burndown invocation (`fixer_model=fable`).
     - `skills/requesting-code-review/code-reviewer.md` — 1 line: the escalation panel ("**Fable + Opus** … the only non-Fable model permitted here" — two matches, one line).
     - `skills/delegating-research-spikes/SKILL.md` — 1 line: delegate dispatches on model **fable**.
     - `skills/delegating-research-spikes/delegate-prompt.md` — 1 line: "You run on model `fable`".
     - `agents/burndown-reviewer.md` — 1 line: the description ("as both Fable and Opus").
     - `agents/burndown-fixer.md` — 1 line: the description (two Fable mentions, one line).
     - `tests/burndown-reviews/MANUAL-VERIFICATION.md` — 1 line: the test prompt (`fixer_model=fable`).
     - Expected total: 21 matching lines across 10 files, and nothing else.

     The two purely additive edits (the § "Spec" precedence note and the step-A version-floor note) appear above only as `fable` tokens, so check their content explicitly: `grep -c 'authoritative for model selection' skills/burndown-reviews/SKILL.md` → 1, and `grep -c '2\.1\.170' skills/burndown-reviews/SKILL.md` → ≥1.
2. Every changed site re-read for internal consistency: dispatch strings, finding-ID stamps, carve-out prose, and examples all agree on the fable+opus pair.
3. **Live dispatch check through the edited skill (post-edit):** the dogfood pass below predates the skill edits — it was a manual orchestrator override, so it proves the dispatches *work* but not that the edited skill text *drives* them. After the edits land, run one live burndown invocation through the updated skill (the `tests/burndown-reviews/MANUAL-VERIFICATION.md` flow works as-is; its prompt now passes `fixer_model=fable`) and confirm from the session transcript that the orchestrator dispatches the two step-A reviewers with `model="fable"` and `model="opus"` and the step-F fixer with `model="fable"`.

**Validation already performed (2026-06-10):** at spec time the live skill still encoded the old pairing, so the orchestrator manually dispatched this spec's own burndown pass with the new pairing (Fable + Opus reviewers, Fable fixer) as an explicit override, ahead of the skill edits landing — dogfooding the design before it lands. Live Task dispatches with `model="fable"` (reviewer and fixer) and `model="opus"` (reviewer) succeeded during this spec's own burndown run; per-round detail is in the trajectory report delivered with the spec review.

## Workflow

All work happens on branch `btc-00002-fable-model-swap` in a dedicated worktree, to be squash-merged to `main` as a single commit. Fork-local only: the squash-merge targets this fork's `main`; no upstream (obra/superpowers) PR.
