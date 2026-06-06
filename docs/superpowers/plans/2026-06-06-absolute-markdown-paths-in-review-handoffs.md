# Absolute markdown paths in review handoffs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use spandapowers:subagent-driven-development (recommended) or spandapowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the two user-facing "here's the markdown to review" handoffs (the `brainstorming` spec gate and the `writing-plans` execution handoff) report an **absolute** path so the user can open it directly in cmux.

**Architecture:** Pure documentation edit to two skill `SKILL.md` files. Each handoff message's path placeholder becomes `<absolute-path>`, and a short instruction tells the agent to evaluate `git rev-parse --show-toplevel`, prefix the repo-relative doc path with the resolved root, and substitute the fully-expanded literal path into the user-facing message (no unexpanded `$(...)`). Internal save-to templates and all other skills are untouched.

**Tech Stack:** Markdown skill files; `grep` for verification; `git` for commits. No code, no tests, no dependencies.

**Spec:** `/Users/btc/src/spandapowers-abs-md-paths/docs/superpowers/specs/2026-06-05-absolute-markdown-paths-in-review-handoffs-design.md`

**Working location:** worktree `/Users/btc/src/spandapowers-abs-md-paths` on branch `main`. All commits land on `main`. Run all commands from the worktree root.

**Verification note:** These edits modify the very skills governing the session, but skills are already loaded — the edits do not change in-flight behavior. Verification is by inspection/`grep`, not behavioral test.

**Line-number caveat:** Any embedded line numbers in this plan (e.g. "line 137", "line 148", "line 119", "line 18") are indicative navigation hints only — they may drift as the files change. The authoritative locators are the verbatim old-text blocks quoted in each task's Step 2, which are matched exactly. If a line number disagrees with the file, trust the quoted block.

---

### Task 1: Absolute path in the `brainstorming` spec review gate

**Files:**
- Modify: `skills/brainstorming/SKILL.md` (the "User Review Gate" block, line 137 message + instruction inserted before line 139)

The current text (lines 137–139) reads exactly:

```
> "Spec written and committed to `<path>`. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

Wait for the user's response. If they request changes, make them and re-run the spec review loop. Only proceed once the user approves.
```

- [ ] **Step 1: Write the failing check (assert the target state is NOT yet present)**

Run from the worktree root:

```bash
cd /Users/btc/src/spandapowers-abs-md-paths
grep -c 'Spec written and committed to `<absolute-path>`' skills/brainstorming/SKILL.md
```

Expected now: `0` (the absolute-path version does not exist yet — this is the RED state).

- [ ] **Step 2: Apply the edit**

Replace the exact old block:

```
> "Spec written and committed to `<path>`. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

Wait for the user's response. If they request changes, make them and re-run the spec review loop. Only proceed once the user approves.
```

with this new block (changes `<path>` → `<absolute-path>` and inserts the instruction paragraph immediately after the quoted message, before the "Wait for the user's response." sentence):

```
> "Spec written and committed to `<absolute-path>`. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

Report `<absolute-path>` as a real absolute path so the user can open it directly: take the spec's repo-relative path and prefix it with the repository root, evaluating `git rev-parse --show-toplevel` and inserting its resolved output (e.g. `/Users/you/src/project/docs/superpowers/specs/2026-01-01-topic-design.md`). The displayed message must contain the fully-expanded path — never an unexpanded `$(...)`.

Wait for the user's response. If they request changes, make them and re-run the spec review loop. Only proceed once the user approves.
```

- [ ] **Step 3: Verify the new text is present and the old placeholder is gone**

```bash
grep -c 'Spec written and committed to `<absolute-path>`' skills/brainstorming/SKILL.md
grep -c 'git rev-parse --show-toplevel' skills/brainstorming/SKILL.md
grep -c 'Spec written and committed to `<path>`' skills/brainstorming/SKILL.md
```

Expected: `1`, then `1`, then `0` (new message present, instruction present, old placeholder gone).

- [ ] **Step 4: Confirm only the intended block changed**

```bash
git diff skills/brainstorming/SKILL.md
```

Expected: the only changes are `<path>` → `<absolute-path>` on the message line and the inserted instruction paragraph. No other lines (e.g. the save-to template at line 119) are touched.

- [ ] **Step 5: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat(brainstorming): report absolute spec path in review handoff"
```

---

### Task 2: Absolute path in the `writing-plans` execution handoff

**Files:**
- Modify: `skills/writing-plans/SKILL.md` (the "Execution Handoff" section, line 146 + line 148 message)

The current text (lines 146–148) reads exactly:

```
After saving the plan, offer execution choice:

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:**
```

- [ ] **Step 1: Write the failing check (assert the target state is NOT yet present)**

```bash
cd /Users/btc/src/spandapowers-abs-md-paths
grep -c 'Plan complete and saved to `<absolute-path>`' skills/writing-plans/SKILL.md
```

Expected now: `0` (RED state).

- [ ] **Step 2: Apply the edit**

Replace the exact old block:

```
After saving the plan, offer execution choice:

**"Plan complete and saved to `docs/superpowers/plans/<filename>.md`. Two execution options:**
```

with this new block (inserts the instruction after the "offer execution choice:" sentence, and changes the bolded message's inline-code path to `<absolute-path>` while preserving the surrounding `**…**` emphasis and the backticks):

```
After saving the plan, offer execution choice. Report the plan path as a real absolute path so the user can open it directly: take the plan's repo-relative path and prefix it with the repository root, evaluating `git rev-parse --show-toplevel` and inserting its resolved output (e.g. `/Users/you/src/project/docs/superpowers/plans/2026-01-01-feature.md`). The displayed message must contain the fully-expanded path — never an unexpanded `$(...)`.

**"Plan complete and saved to `<absolute-path>`. Two execution options:**
```

- [ ] **Step 3: Verify the new text is present, formatting preserved, and the old placeholder is gone**

```bash
grep -cF '**"Plan complete and saved to `<absolute-path>`. Two execution options:' skills/writing-plans/SKILL.md
grep -c 'git rev-parse --show-toplevel' skills/writing-plans/SKILL.md
grep -c '`docs/superpowers/plans/<filename>.md`. Two execution options' skills/writing-plans/SKILL.md
grep -c 'Save plans to:' skills/writing-plans/SKILL.md
```

Expected: `1` (new message present with bold `**` and backticks intact), `1` (instruction present), `0` (old handoff placeholder gone), `1` (the line-18 "Save plans to:" save-to template still present and unchanged — it is a non-goal).

- [ ] **Step 4: Confirm only the intended block changed**

```bash
git diff skills/writing-plans/SKILL.md
```

Expected: only the "After saving the plan…" sentence gained the instruction, and the bold message's path became `<absolute-path>`. The `**` emphasis and backticks are intact. The "Save plans to:" template at line 18 is untouched.

- [ ] **Step 5: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat(writing-plans): report absolute plan path in execution handoff"
```

---

### Task 3: Whole-change verification

**Files:** none modified (verification only).

- [ ] **Step 1: Confirm the diff touches only the two skill files**

```bash
cd /Users/btc/src/spandapowers-abs-md-paths
git diff --stat HEAD~2..HEAD -- skills/
```

**Precondition:** run this check ONLY after Tasks 1 and 2 are both committed. `HEAD~2` is the commit immediately before Task 1 — i.e. the diff spans exactly the two skill-edit commits made in Task 1 and Task 2 (Task 3 itself makes no commit before this check). If `git diff --stat HEAD~2..HEAD -- skills/` produces empty output, that means the Task 1/Task 2 commits have not landed yet — empty output is a FAILURE, not a pass.

Expected: exactly two files listed — `skills/brainstorming/SKILL.md` and `skills/writing-plans/SKILL.md`. No other skills changed.

- [ ] **Step 2: Confirm both handoffs now report an absolute path**

```bash
grep -rn '`<absolute-path>`' skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md
grep -c 'git rev-parse --show-toplevel' skills/brainstorming/SKILL.md skills/writing-plans/SKILL.md
```

Expected: `<absolute-path>` appears in each handoff message. The first grep returns **2 lines for `skills/brainstorming/SKILL.md`** — the handoff message line AND the inserted instruction sentence, which also contains `` `<absolute-path>` `` ("Report `<absolute-path>` as a real absolute path…") — and **1 line for `skills/writing-plans/SKILL.md`** (only the handoff message line; the writing-plans instruction sentence refers to "the plan's repo-relative path" and does not contain the `` `<absolute-path>` `` token). Do not be surprised by the extra brainstorming match. The `git rev-parse --show-toplevel` instruction count is `1` per file.

- [ ] **Step 3: Confirm no save-to template regressed**

```bash
grep -n 'docs/superpowers/specs/YYYY-MM-DD' skills/brainstorming/SKILL.md
grep -n 'docs/superpowers/plans/YYYY-MM-DD' skills/writing-plans/SKILL.md
```

Expected: the brainstorming `docs/superpowers/specs/YYYY-MM-DD` grep returns **2 lines** (line 31, the checklist "Write design doc" step, and line 119, under the "After the Design / Documentation" bullet — both reference the specs save-to template, both still repo-relative and unchanged). The writing-plans `docs/superpowers/plans/YYYY-MM-DD` grep returns **1 line** (line 18, "Save plans to:"). All save-to template lines are still present and still repo-relative (non-goals preserved).
