# Absolute markdown paths in review handoffs

**Date:** 2026-06-05
**Status:** Design approved; in spec review (this is the spec currently under burndown review)

## Problem

When a Superpowers skill finishes writing a markdown artifact and hands it back
for the user to review, it reports a **repo-relative** path. For example,
`brainstorming` says:

> "Spec written and committed to `<path>`. Please review it…"

and `writing-plans` says:

> "Plan complete and saved to `docs/superpowers/plans/<filename>.md`…"

A relative path is not directly clickable/openable in the user's editor (cmux).
The user has to manually resolve it against the working directory — and in a
git worktree the working directory is not the main checkout, so the relative
path is ambiguous. The user wants every "here is the markdown to review" handoff
to report an **absolute** path so it can always be opened directly.

## Scope

Exactly the two user-facing review handoffs where a skill hands the user a
markdown file to open and review:

1. **`skills/brainstorming/SKILL.md`** — the spec review gate (the
   `> "Spec written and committed to \`<path>\`…"` message, line 137).
2. **`skills/writing-plans/SKILL.md`** — the execution handoff (the
   `**"Plan complete and saved to \`docs/superpowers/plans/<filename>.md\`. Two execution options:**`
   message, line 148).

The verbatim quoted handoff messages above are the authoritative locators for
the edits. The cited line numbers (137, 148) are indicative only and may shift
if the files change before the edit is applied; locate the edit by matching the
quoted message text, not the line number.

### Explicit non-goals

- **Internal save-to templates stay repo-relative.** Instructions that tell the
  agent *where to write* a file (e.g. `Save plans to:
  docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`,
  `save to docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`) are not
  user-facing review handoffs and are left unchanged. Only the message that asks
  the user to *open and review* the file is changed.
- **No other skills are touched.** `executing-plans` and
  `subagent-driven-development` only read these files internally;
  `requesting-code-review` dispatches reviewer subagents; `burndown-reviews`
  emits an inline trajectory table rather than a file path; the `.context.md`
  file is internal to the burndown loop and never handed to the user. None of
  these present a markdown file for the user to open.
- **No new script or dependency.** See Mechanism below.

## Mechanism

Inline instruction only — no committed helper script. Rationale:

- The absolute path is a one-liner: prefix the repo-relative path with the
  repository root. Skills here already inline this idiom — e.g.
  `skills/using-git-worktrees/SKILL.md` uses `git rev-parse --show-toplevel`
  directly.
- Superpowers is zero-dependency by design; a committed script is a new
  maintenance/coupling surface for something trivial.
- The agent already knows the file it just wrote — it only needs to be *told* to
  report it as an absolute path.

Each of the two handoff messages is updated so that:

- The displayed path placeholder is an **absolute** path (e.g.
  `<absolute-path>` rather than `<path>` or a `docs/…`-relative example).
- A short instruction tells the agent to construct the absolute path by
  prefixing the repo-relative doc path with the repository root, e.g.
  `$(git rev-parse --show-toplevel)/docs/superpowers/specs/…`, so the user can
  open it directly.

`git rev-parse --show-toplevel` returns the root of the *current worktree* —
which is exactly where the spec/plan file physically lives — so the resulting
absolute path points at the real on-disk file and is directly openable. This is
precisely what resolves the relative-path ambiguity called out in the Problem
section: a worktree's working directory is not the main checkout, so a
repo-relative path is ambiguous, but a worktree-local *absolute* path is not.
Worktree-local absolute is the intended, correct, openable target — no
canonical/main-checkout resolution is wanted or performed.

Note this is an instruction the agent *evaluates*, not a literal string to
display: the agent runs `git rev-parse --show-toplevel`, takes its resolved
output, and substitutes that literal absolute path into the user-facing handoff
message. The displayed message must contain the fully-expanded path with **no
unexpanded `$(...)`** left in it.

## Approach / changes

### 1. `skills/brainstorming/SKILL.md`

Update the spec review-gate message (line 137) so the reported path is
absolute. The placeholder inside the quoted handoff message becomes an absolute
path. The absolute-path instruction is added as a short sentence placed
immediately *after* the quoted handoff message block and *before* the existing
"Wait for the user's response." instruction in the User Review Gate (telling the
agent to report the absolute path: repo root + relative path). The surrounding
step text ("User Review Gate") is otherwise unchanged.

### 2. `skills/writing-plans/SKILL.md`

Update the Execution Handoff message (line 148) so the reported plan path is
absolute, with the same absolute-path instruction. The path placeholder here
lives inside a bolded inline-code span — the message reads
`**"Plan complete and saved to \`docs/superpowers/plans/<filename>.md\`. Two execution options:**` —
so the existing path token to replace is the backtick-wrapped inline-code span
`` `docs/superpowers/plans/<filename>.md` ``, which becomes the absolute-path
placeholder. The edit must make the path absolute *while preserving* the
surrounding `**…**` emphasis and the backticks around the path. The "Save plans
to:" line at the top of the skill stays repo-relative (it is a save-to
template, a non-goal).

## Testing / verification

This is a documentation/behavior-shaping change to two skill files. Verification:

- **Inline review:** confirm both edits render the intended message, the
  placeholder is unambiguously absolute, and the absolute-path instruction is
  present and correct.
- **No collateral edits:** `git diff` touches only the two SKILL.md files and
  changes only the two handoff messages (plus minimal supporting instruction
  text) — no save-to templates, no other skills.
- Per CLAUDE.md, full adversarial eval is reserved for behavior-shaping content
  like Red Flags tables and rationalization lists. This change adjusts a
  user-facing report string and adds a path-construction instruction; it does
  not alter discipline-shaping content, so a careful inline review is the
  appropriate bar.

## Delivery

- Work is done in a git worktree at `/Users/btc/src/spandapowers-abs-md-paths`
  checked out on `main`, to avoid disturbing the in-flight
  `delegating-research-spikes` branch.
- Commits land on `main` directly, per the user's instruction.
- This is a fork-local workflow change for the user's cmux setup; it is not
  destined for an upstream PR.
