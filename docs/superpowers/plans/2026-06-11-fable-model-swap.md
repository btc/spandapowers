# Fable Model Swap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use spandapowers:subagent-driven-development (recommended) or spandapowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shift every live Opus/Sonnet reference in the spandapowers skills up one tier — Opus→Fable (`model="fable"`), Sonnet→Opus (`model="opus"`) — per the spec at `docs/superpowers/specs/2026-06-10-fable-model-swap-design.md` (one exception: a model-specific behavioral prediction is dropped rather than swapped — Task 7).

**Architecture:** Pure text edits to skill/agent markdown — no code, no tests to write. Ten files change; every edit site is enumerated below with verbatim old→new text. Verification is mechanical: grep baselines were measured pre-edit (28 `\bopus\b` lines / 13 `sonnet` lines / 4 `fixer_model=opus` sites / 0 `fable` in `skills/ agents/ tests/`), and the spec defines exact expected post-state inventories. Task 8 runs the full battery.

**Tech Stack:** Markdown, grep. Branch `btc-00002-fable-model-swap` (exists) in this worktree; squash-merge to this fork's `main` later — no upstream PR.

**Read first:** the spec's "Changes" and "Verification" sections. All line numbers below are pre-edit. Edit in place — do not reflow or split existing lines (the verification line-counts assume it). The two additive notes in Task 1 must each land as their own physical line. Quoting legend: in inline Old/New strings, a backslash-backtick (\`) denotes a literal backtick in the target file — strip the backslash before matching; fenced code blocks are byte-exact. For zero-expectation greps, no matches IS the pass condition: the command exits 1 with empty output (or prints `0` for `-c` forms) — do not treat that nonzero exit as a command failure.

**Baseline provenance:** the spec's baselines were measured at `7574d2a`; the only commits between `7574d2a` and the pre-edit ref `93730dc` (`1ed1584` and `93730dc` itself) touched only `docs/`, so the spec's baselines hold unchanged at `93730dc`.

---

### Task 1: `skills/burndown-reviews/SKILL.md` (9 edit steps + verify + commit; 8 fable-bearing lines post-edit)

**Files:**
- Modify: `skills/burndown-reviews/SKILL.md` — replace on pre-edit lines 3, 21, 37, 44, 59, 74, 75; insert after pre-edit line 26 (precedence note) and after the step-A dispatch line (version-floor note)

Step ordering: all in-place replacements (Steps 1–7) run before the two insertions (Steps 8–9), so every cited pre-edit line number is still valid at the moment its step executes.

- [ ] **Step 1: Frontmatter description (line 3)** — replace the phrase:

Old: `Drives Opus + Sonnet reviewers concurrently`
New: `Drives Fable + Opus reviewers concurrently`

- [ ] **Step 2: Inputs prose fixer constant (line 21)** — replace the full line:

Old:
```
- `fixer_model` — always `opus` for all stages. Retained as a fixed symbolic constant for call-site traceability and minimal diff; **not** a tunable parameter — no code path may set it to anything other than `opus`.
```
New:
```
- `fixer_model` — always `fable` for all stages. Retained as a fixed symbolic constant for call-site traceability and minimal diff; **not** a tunable parameter — no code path may set it to anything other than `fable`.
```

- [ ] **Step 3: Pseudocode fixer constant (line 37)** — replace:

Old: `fixer_model_for_stage = opus   # fixed for all stages; not tunable`
New: `fixer_model_for_stage = fable   # fixed for all stages; not tunable`

- [ ] **Step 4: Step A dispatch line (line 44)** — four substring replacements plus one keep-as-is check on this one line (do not split the line):
  1. `one with \`model="opus"\`, one with \`model="sonnet"\`` → `one with \`model="fable"\`, one with \`model="opus"\``
  2. `as \`opus-r{round}-{n}\` / \`sonnet-r{round}-{n}\`` → `as \`fable-r{round}-{n}\` / \`opus-r{round}-{n}\``
  3. `the \`opus\`+\`sonnet\` pairing is intentional` → `the \`fable\`+\`opus\` pairing is intentional`
  4. `This is the only *always-on* reviewer-pair Sonnet usage and it stays` → `This is the only *always-on* reviewer-pair Opus usage and it stays`
  5. Keep the trailing `(the #2/#3 escalated review panels are a separate, gated carve-out)` parenthetical exactly as is — it is load-bearing (post-swap, Opus appears in both the always-on pair and the gated panels; this sentence covers only the former).

- [ ] **Step 5: Step F fixer dispatch (line 59)** — replace the phrase:

Old: `\`model=fixer_model_for_stage\` (always \`opus\`)`
New: `\`model=fixer_model_for_stage\` (always \`fable\`)`

- [ ] **Step 6: Round-8 inventory stamps (line 74)** — one substring replacement plus one keep-as-is check:
  1. `typically \`opus-r8-{n}\` / \`sonnet-r8-{n}\` for the initial inventory; \`opus-r{N}-{n}\` / \`sonnet-r{N}-{n}\` for a post-extension inventory` → `typically \`fable-r8-{n}\` / \`opus-r8-{n}\` for the initial inventory; \`fable-r{N}-{n}\` / \`opus-r{N}-{n}\` for a post-extension inventory`
  2. The `(e.g., \`r18\` after 10 extension rounds concluding at round 18)` parenthetical is unchanged — it contains no model name.

- [ ] **Step 7: Round-8 merge variables (line 75)** — replace the phrase:

Old: `Merge \`final_opus + final_sonnet + deferred_findings\``
New: `Merge \`final_fable + final_opus + deferred_findings\``

(Same-name/different-referent warning: post-swap, live-skill `final_opus` is the *second* reviewer — the ex-Sonnet slot — while the 2026-05-04 spec's pseudocode uses `final_opus` for the *first*. Do not add any mapping note to the skill text — it would reintroduce a `sonnet` token; the correspondence map lives in the swap spec.)

- [ ] **Step 8: Precedence note (after line 26, the § "Spec" authority paragraph)** — after the paragraph ending "consult the spec for the why and the edge cases.", add a new paragraph (its own line, blank line before it). Line 26 is still accurate at this point: Steps 1–7 replaced text in place and inserted no lines:

```
Model names in the 2026-05-04 spec predate the 2026-06-10 Fable swap (see `docs/superpowers/specs/2026-06-10-fable-model-swap-design.md`); this skill file is authoritative for model selection (reviewer pair, fixer model, and any model-override behavior), including where the spec's pseudocode and dispatch table say otherwise.
```

- [ ] **Step 9: Version-floor note** — add immediately after the step-A dispatch line you edited in Step 4 (the list-item-1 line containing the reviewer dispatch; don't rely on the pre-edit line number — Step 8's insertion shifted it). Insert exactly three physical lines: a blank line, then the note as its own line with three leading spaces, then another blank line. The blank line before makes the note render as a separate continuation paragraph of list item 1, and the three-space indent keeps it inside the list item; the blank line after is required because the next line (`2. **(B) Judge each finding**`) cannot interrupt a paragraph per CommonMark (only `1.`-numbered items can) — without it, item 2 lazily continues the note paragraph and the rendered list breaks. The trailing blank line matches no grep pattern, so it affects no line-count verification. (Side effect: the surrounding list is currently "tight"; these blank lines deliberately make item 1 render "loose". They are load-bearing — do not remove them as cleanup, or the rendering bug above returns.):

```
   The `fable` model slug requires Claude Code ≥ 2.1.170 (verified floor); builds without `fable` support fail loudly at dispatch validation.
```

- [ ] **Step 10: Verify this file** — run from the worktree root:

```bash
grep -ci 'sonnet' skills/burndown-reviews/SKILL.md       # expected: 0
grep -rni '\bopus\b' skills/burndown-reviews/SKILL.md | wc -l   # expected: 3 (description, step-A line, round-8 stamps line)
grep -c 'authoritative for model selection' skills/burndown-reviews/SKILL.md  # expected: 1
grep -c '2\.1\.170' skills/burndown-reviews/SKILL.md     # expected: 1
grep -c 'fixer_model_for_stage = fable' skills/burndown-reviews/SKILL.md  # expected: 1
grep -rni '\bfable\b' skills/burndown-reviews/SKILL.md | wc -l   # expected: 8 (if 7: the Step 9 note merged onto the already-fable-bearing step-A dispatch line — placement bug, not a missed swap. A misplaced Step 8 note still creates a new fable-bearing line, keeping the count at 8, so that bug is grep-invisible — it is caught only by the Task 8 Step 7 re-read)
```

- [ ] **Step 11: Commit**

```bash
git add skills/burndown-reviews/SKILL.md
git commit -m "feat(burndown-reviews): reviewer pair fable+opus, fixer fable; precedence + version-floor notes"
```

---

### Task 2: Burndown call sites (3 one-line edits)

**Files:**
- Modify: `skills/brainstorming/SKILL.md:45`
- Modify: `skills/writing-plans/SKILL.md:142`
- Modify: `skills/subagent-driven-development/SKILL.md:284` (⚠ shared with Task 3 — see ordering note there; do not run Tasks 2 and 3 in parallel)

- [ ] **Step 1: In each of the three files, replace the substring on the cited line:**

Old: `fixer_model=opus`
New: `fixer_model=fable`

The three lines are the burndown-reviews invocations (brainstorming checklist step 8.3; writing-plans "Burndown Review Pass"; SDD impl-stage invocation). Touch nothing else on those lines.

- [ ] **Step 2: Verify**

```bash
grep -rn 'fixer_model=opus' skills/  # expected: no output
grep -rln 'fixer_model=fable' skills/  # expected: exactly the 3 files above (burndown-reviews/SKILL.md never uses this exact form — its sites are prose and spaced pseudocode)
```

(Note: the fourth `fixer_model=opus` site is `tests/burndown-reviews/MANUAL-VERIFICATION.md` — Task 7, not here. After this task, `grep -rn 'fixer_model=opus' tests/` still returns 1 hit; that is expected until Task 7.)

- [ ] **Step 3: Commit**

```bash
git add skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md skills/subagent-driven-development/SKILL.md
git commit -m "feat(skills): burndown call sites pass fixer_model=fable"
```

---

### Task 3: `skills/subagent-driven-development/SKILL.md` model statements (3 edits)

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md` (pre-edit lines 103, 118, 119, 272)

**Ordering: run after Task 2.** Tasks 2 and 3 both modify this file (Task 2 edits line 284), so they are NOT independent — do not dispatch them in parallel; Step 4's expected counts assume Task 2 already landed.

- [ ] **Step 1: Line 103** — replace the phrase:

Old: `All SDD subagents run **Opus** —`
New: `All SDD subagents run **Fable** —`

Do NOT touch line 105 ("the lever is not a bigger model (there isn't one)…") — it names no model and stays true under Fable; intentionally unchanged.

- [ ] **Step 2: Lines 118–119** — two replacements:

Old (118): `re-dispatch (still Opus)`
New (118): `re-dispatch (still Fable)`

Old (119): `there is no more capable model than Opus, so the lever is multi-agent decomposition`
New (119): `there is no more capable model than Fable, so the lever is multi-agent decomposition`

- [ ] **Step 3: Line 272 escalation panel** — replace the phrase:

Old: `a multi-model panel (**Opus + Sonnet** — review-diversity carve-out)`
New: `a multi-model panel (**Fable + Opus** — review-diversity carve-out)`

Implementer note: Opus's presence beside line 119's "no more capable model than Fable" is deliberate cross-model review diversity, not a capability ranking — do not "consistency-fix" it away.

- [ ] **Step 4: Verify**

```bash
grep -ci 'sonnet' skills/subagent-driven-development/SKILL.md  # expected: 0
grep -rni '\bopus\b' skills/subagent-driven-development/SKILL.md | wc -l  # expected: 1 (the line-272 panel)
grep -c 'still Opus\|than Opus\|run \*\*Opus\*\*' skills/subagent-driven-development/SKILL.md  # expected: 0 (pre-edit baseline at 93730dc: 3 matching lines — 103, 118, 119)
```

(Expected 1 assumes Task 2 already landed — line 284's `fixer_model=opus` also matches `\bopus\b`, since `=` is a word boundary. If Task 2 has not run yet, expect 2: the line-272 panel plus the line-284 call site.)

- [ ] **Step 5: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md
git commit -m "feat(sdd): all subagents run Fable; escalation panel Fable+Opus"
```

---

### Task 4: `skills/requesting-code-review/code-reviewer.md` (1 edit)

**Files:**
- Modify: `skills/requesting-code-review/code-reviewer.md:114`

- [ ] **Step 1: Replace the phrase on line 114:**

Old: `(**Opus + Sonnet** — a deliberate review-diversity carve-out, the only non-Opus model permitted here)`
New: `(**Fable + Opus** — a deliberate review-diversity carve-out, the only non-Fable model permitted here)`

("here" scopes the claim to this escalation panel, mirroring the original's semantics exactly.)

- [ ] **Step 2: Verify**

```bash
grep -ci 'sonnet' skills/requesting-code-review/code-reviewer.md  # expected: 0
grep -rni '\bopus\b' skills/requesting-code-review/code-reviewer.md | wc -l  # expected: 1
```

- [ ] **Step 3: Commit**

```bash
git add skills/requesting-code-review/code-reviewer.md
git commit -m "feat(code-review): escalation panel Fable+Opus"
```

---

### Task 5: `skills/delegating-research-spikes/` (2 edits)

**Files:**
- Modify: `skills/delegating-research-spikes/SKILL.md:54`
- Modify: `skills/delegating-research-spikes/delegate-prompt.md:27`

- [ ] **Step 1: SKILL.md line 54** — replace the phrase:

Old: `model **opus** using \`delegate-prompt.md\``
New: `model **fable** using \`delegate-prompt.md\``

(Substring, not the full line: the sentence wraps across lines 53–54, and line 54 continues past the quoted text with a comma — `model **opus** using \`delegate-prompt.md\`, doing two distinct things:` — so match the quoted phrase only; a full-line match will fail.)

- [ ] **Step 2: delegate-prompt.md line 27** — replace the line:

Old: `- **You run on model \`opus\`.**`
New: `- **You run on model \`fable\`.**`

- [ ] **Step 3: Verify** — note this skill directory also contains `test-scenarios.md` (historical transcripts, OUT OF SCOPE — do not edit it; its opus/sonnet hits are expected to remain):

```bash
grep -rni '\bopus\b' skills/delegating-research-spikes/SKILL.md skills/delegating-research-spikes/delegate-prompt.md | wc -l  # expected: 0
grep -c 'model \*\*fable\*\*' skills/delegating-research-spikes/SKILL.md  # expected: 1
```

- [ ] **Step 4: Commit**

```bash
git add skills/delegating-research-spikes/SKILL.md skills/delegating-research-spikes/delegate-prompt.md
git commit -m "feat(research-spikes): delegate dispatches on fable"
```

---

### Task 6: `agents/` descriptions (2 edits)

**Files:**
- Modify: `agents/burndown-reviewer.md:4`
- Modify: `agents/burndown-fixer.md:4`

Frontmatter `model: inherit` stays unchanged in both files.

- [ ] **Step 1: burndown-reviewer.md line 4** — replace the phrase:

Old: `Dispatched concurrently as both Opus and Sonnet by the burndown-reviews skill`
New: `Dispatched concurrently as both Fable and Opus by the burndown-reviews skill`

- [ ] **Step 2: burndown-fixer.md line 4** — replace the phrase:

Old: `the orchestrator dispatches it with Opus for all stages (the fixer model is always Opus and is not tunable)`
New: `the orchestrator dispatches it with Fable for all stages (the fixer model is always Fable and is not tunable)`

- [ ] **Step 3: Verify**

```bash
grep -ci 'sonnet' agents/*.md  # expected: 0 for every file
grep -rni '\bopus\b' agents/ | wc -l  # expected: 1 (burndown-reviewer.md description; burndown-fixer.md drops out entirely)
grep -c 'model: inherit' agents/burndown-reviewer.md agents/burndown-fixer.md  # expected: 1 each
```

(`agents/` also contains a third file, `agents/code-reviewer.md` — it has no model references and is untouched by this plan; expect it in the first command's output with count 0.)

- [ ] **Step 4: Commit**

```bash
git add agents/burndown-reviewer.md agents/burndown-fixer.md
git commit -m "feat(agents): burndown agent descriptions name Fable/Opus"
```

---

### Task 7: `tests/burndown-reviews/MANUAL-VERIFICATION.md` (2 edits)

**Files:**
- Modify: `tests/burndown-reviews/MANUAL-VERIFICATION.md` (pre-edit lines 14, 42)

- [ ] **Step 1: Line 14 test prompt** — replace the substring:

Old: `fixer_model=opus`
New: `fixer_model=fable`

- [ ] **Step 2: Line 42** — replace the full line. The old parenthetical is a behavioral prediction about the old pair; swapping names would fabricate an unverified claim about Fable, so it is dropped:

Old:
```
- A reviewer (likely Sonnet, since Opus tends to respect locked decisions more aggressively) will probably flag the denormalization as an anti-pattern.
```
New:
```
- A reviewer will probably flag the denormalization as an anti-pattern.
```

- [ ] **Step 3: Verify**

```bash
grep -rni 'sonnet\|\bopus\b' tests/ | wc -l  # expected: 0
grep -c 'fixer_model=fable' tests/burndown-reviews/MANUAL-VERIFICATION.md  # expected: 1
```

- [ ] **Step 4: Commit**

```bash
git add tests/burndown-reviews/MANUAL-VERIFICATION.md
git commit -m "feat(tests): manual-verification prompt uses fixer_model=fable; drop stale behavioral prediction"
```

---

### Task 8: Full verification battery (no edits)

Run every check from the spec's § Verification, from the worktree root. All expected values below assume Tasks 1–7 landed with in-place edits (no line reflowing).

- [ ] **Step 1: Sonnet gone**

```bash
grep -rni 'sonnet' skills/ agents/ tests/
grep -rli 'sonnet' skills/ agents/ tests/   # file-list cross-check
```
Expected: exactly 5 matching lines in exactly 2 files — `skills/delegating-research-spikes/test-scenarios.md` (3 lines), `skills/writing-skills/anthropic-best-practices.md` (2 lines). Baseline was 13. The `-l` cross-check must list exactly those two files — the line count alone can mask a same-total regression (e.g., one historical sonnet line removed while one live sonnet is missed still totals 5). RELEASE-NOTES.md also retains a historical Sonnet reference — intentionally outside this scoped grep; the Step 4 repo-wide check covers it.

- [ ] **Step 2: Surviving-opus invariant**

```bash
grep -rni '\bopus\b' skills/ agents/ tests/
grep -rni '\bopus\b' skills/ agents/ tests/ | wc -l                          # count cross-check: expected 14
grep -rni '\bopus\b' skills/ agents/ tests/ | cut -d: -f1 | sort | uniq -c   # per-file cross-check: must match the per-file counts below
```
Expected: exactly 14 matching lines across exactly 6 files, and nothing else (baseline 28):
- `skills/burndown-reviews/SKILL.md` — 3 (description; step-A line; round-8 line)
- `skills/subagent-driven-development/SKILL.md` — 1 (line-272 panel)
- `skills/requesting-code-review/code-reviewer.md` — 1 (panel)
- `agents/burndown-reviewer.md` — 1 (description)
- `skills/delegating-research-spikes/test-scenarios.md` — 5 (historical)
- `skills/writing-skills/anthropic-best-practices.md` — 3 (historical)

Any other hit is a missed swap. (`final_opus` does not match — `_` is a word character.)

- [ ] **Step 3: Stale patterns — all must return zero**

```bash
grep -rn 'fixer_model=opus' skills/ agents/ tests/
grep -rn 'fixer_model_for_stage = opus' skills/ agents/ tests/
grep -rnF '(always `opus`)' skills/ agents/ tests/
grep -rn 'still Opus' skills/ agents/ tests/
grep -rn 'than Opus' skills/ agents/ tests/
grep -rnF 'run on model `opus`' skills/ agents/ tests/
grep -rnF 'model **opus**' skills/ agents/ tests/
grep -rnF 'run **Opus**' skills/ agents/ tests/
```
Expected: no output from any of them.

A zero only counts as evidence if the pattern matched something pre-edit (a typo'd pattern also returns nothing). Confirm each pattern's baseline against the pre-edit ref `93730dc` (a docs-only commit — `skills/ agents/ tests/` are identical in every commit up to the start of Task 1, so any later docs-only ref gives the same counts) — e.g. `git grep -c 'still Opus' 93730dc -- skills/ agents/ tests/` for the plain patterns, `git grep -cF 'run **Opus**' 93730dc -- skills/ agents/ tests/` for the `-F` ones. Expected pre-edit site counts: `fixer_model=opus` → 4; each of the other 7 patterns (`fixer_model_for_stage = opus`, ``(always `opus`)``, `still Opus`, `than Opus`, ``run on model `opus` ``, `model **opus**`, `run **Opus**`) → exactly 1. Output shape: `git grep -c` prints per-file counts (`93730dc:<path>:<n>`), so the `fixer_model=opus` baseline appears as four lines with `:1` each (four files, one site per file), and each single-site pattern as one such line — not a literal total on one line.

- [ ] **Step 4: Repo-wide scope check** — run from the worktree root:

```bash
git grep -niP '\bopus\b|sonnet' -- ':!docs'
git grep -niP '\bfable\b' -- ':!docs'   # repo-wide positive check (pre-edit baseline: 0 hits)
```
The fable form must hit exactly the 10 inventory files from Step 5 and nothing else — a stray `fable` edit outside `skills/ agents/ tests/` (README, commands/, hooks/) would otherwise pass the whole battery undetected. Same PCRE precheck/fallback as below applies.

For the opus/sonnet form — expected: hits in exactly 7 files — the 6 files from Step 2 plus `RELEASE-NOTES.md` (1 historical line). Any other file is a missed live reference. `git grep` searches tracked files only, so the 7-file assertion holds even if untracked top-level dirs (e.g., `node_modules`) appear. Use `-P`, not `-E`: this machine's `git grep -E` does not honor `\b` (verified — the `-E` form missed 5 of the 13 pre-edit baseline files). The `-P` form was verified pre-edit at `93730dc` to reproduce the 13-file baseline with per-file line counts identical to the old `grep -rniE … --exclude-dir` form. PCRE precheck: `git grep -P` requires a PCRE-enabled git build — first run `git grep -niP '\bopus\b' -- RELEASE-NOTES.md` (should print the one historical line); if git errors with "not built with PCRE support", fall back to `grep -rniE '\bopus\b|sonnet' . --exclude-dir=.git --exclude-dir=docs` — itself verified pre-edit to reproduce the 13-file baseline on this machine (caveat: plain grep also walks untracked dirs, so discount hits in untracked paths — only relevant if untracked root-level dirs exist).

- [ ] **Step 5: Positive fable inventory**

```bash
grep -rni '\bfable\b' skills/ agents/ tests/
grep -rni '\bfable\b' skills/ agents/ tests/ | wc -l                          # count cross-check: expected 21
grep -rni '\bfable\b' skills/ agents/ tests/ | cut -d: -f1 | sort | uniq -c   # per-file cross-check: must match the per-file counts below
```
Expected: exactly 21 matching lines across exactly 10 files (baseline 0): `skills/burndown-reviews/SKILL.md` 8; `skills/brainstorming/SKILL.md` 1; `skills/writing-plans/SKILL.md` 1; `skills/subagent-driven-development/SKILL.md` 5; `skills/requesting-code-review/code-reviewer.md` 1; `skills/delegating-research-spikes/SKILL.md` 1; `skills/delegating-research-spikes/delegate-prompt.md` 1; `agents/burndown-reviewer.md` 1; `agents/burndown-fixer.md` 1; `tests/burndown-reviews/MANUAL-VERIFICATION.md` 1. If `skills/burndown-reviews/SKILL.md` shows 7, check whether the Task 1 Step 9 version-floor note was appended to the already-fable-bearing step-A dispatch line instead of landing standalone — a placement bug, not a missed swap. (A misplaced Task 1 Step 8 note would still create a new fable-bearing line, keeping the count at 8 — that bug passes every grep here; Step 7 catches it.)

- [ ] **Step 6: Additive-note content checks**

```bash
grep -c 'authoritative for model selection' skills/burndown-reviews/SKILL.md  # expected: 1
grep -c '2\.1\.170' skills/burndown-reviews/SKILL.md                          # expected: 1
```

(The spec allows ≥1 for the `2.1.170` count; the plan tightens to exactly 1 because only the version-floor note introduces a `2.1.170` token.)

- [ ] **Step 7: Consistency re-read** — re-read each changed site in full (all ten changed files' edited lines) and confirm dispatch strings, finding-ID stamps, carve-out prose, and examples all agree on the fable+opus pair. In `skills/burndown-reviews/SKILL.md`, specifically confirm the Task 1 Step 8 precedence note landed as its own standalone paragraph (not appended to the authority paragraph's line) — that misplacement is not grep-detectable and this re-read is the only check that catches it. No commit needed if clean; if any check failed, fix and add a follow-up commit (the squash-merge collapses history anyway).

---

### Task 9: Post-merge smoke test (deferred — runs AFTER squash-merge, not in this worktree)

**STOP — execution-loop agents do not run this task.** Tasks 1–8 complete the in-worktree work; report done after Task 8. Task 9 belongs to the user at the finishing-a-development-branch gate (post-squash-merge, or via the documented pre-merge alternative below) — its checkboxes must not be auto-executed from the worktree session.

Task 9 is intentionally outside the in-worktree execution loop — completing Tasks 1–8 completes the branch work; Task 9 is the post-integration gate. Sessions load skills from the installed plugin (the main checkout), not this worktree — so the default path runs the end-to-end check after the swap is merged (a pre-merge alternative exists; see the note below the steps). The squash-merge itself is performed via spandapowers:finishing-a-development-branch (the standard branch-completion path) once Tasks 1–8 are done and reviewed; at that gate, surface the pre-merge vs post-merge smoke-test choice to the user explicitly (default: post-merge, with the Step 4 failure path below).

- [ ] **Step 1:** After squash-merge to `main`, reload plugins (`/reload-plugins`) or start a fresh session.
- [ ] **Step 2:** Run the `tests/burndown-reviews/MANUAL-VERIFICATION.md` flow (its prompt now passes `fixer_model=fable`).
- [ ] **Step 3:** Confirm from the session transcript: the orchestrator dispatches the two step-A reviewers with `model="fable"` and `model="opus"`, and the step-F fixer with `model="fable"`. Requires Claude Code ≥ 2.1.170 (active version verified 2026-06-10).
- [ ] **Step 4 (failure path):** If the transcript shows wrong-model dispatches, fix forward on `main` (or revert the squash commit) and re-run the smoke test before considering the swap done.

**Pre-merge alternative (optional):** a smoke test before merging is possible by pointing the installed checkout at the branch commit. Precondition: verify the primary checkout's tree is clean — `git -C /Users/btc/src/spandapowers status --porcelain` must print nothing (stash first if dirty); a dirty tree can fail the detach or carry changes across the detach/restore cycle. Then: `git -C /Users/btc/src/spandapowers checkout --detach btc-00002-fable-model-swap`, reload plugins, run the MANUAL-VERIFICATION flow, then `git -C /Users/btc/src/spandapowers checkout main` and reload again. Trade-off: it temporarily detaches the user's primary checkout and needs two plugin reloads — which is why the default path is post-merge verification with the Step 4 fix-forward/revert failure path.
