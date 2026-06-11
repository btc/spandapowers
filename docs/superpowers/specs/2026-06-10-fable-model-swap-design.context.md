# Context: Fable Model Swap

## Original request (paraphrased)

Claude Fable 5 is here. Update the spandapowers skills to use Fable 5 instead of Opus, doing the work on a branch (in a worktree) so it squash-merges to a single commit. For the burndown reviews, switch the reviewer pair from Sonnet + Opus to Opus + Fable. The mapping is general: where Opus is used, use Fable; where Sonnet is used, use Opus. The user expected this to be fairly mechanical and simple, with a research spike to find the switch points.

## Locked-in decisions

- **Scope: live content only.** Skills, agents, and `tests/burndown-reviews/MANUAL-VERIFICATION.md`. Historical artifacts (past specs/plans under `docs/`, `RELEASE-NOTES.md`, `skills/delegating-research-spikes/test-scenarios.md` transcripts, `skills/writing-skills/anthropic-best-practices.md` quoted guidance) are untouched. No new RELEASE-NOTES entry.
- **Approach: literal `fable` slug.** Claude Code was upgraded to 2.1.170 during the brainstorm (verified live: a Task dispatch with `model="fable"` succeeded). Skills say `model="fable"` directly; no inherit/frontmatter workarounds. Updated skills require CC ≥ 2.1.170; older builds fail loudly at dispatch validation.
- **Mapping is uniform:** opus → fable, sonnet → opus, applied at every live dispatch/model-reference site, including the burndown fixer (`fixer_model=fable`, still fixed and non-tunable), SDD's all-Opus rule (becomes all-Fable), the escalated review panels (Fable + Opus), and the research-spike delegate (fable).
- **Behavioral predictions are not mechanically swapped.** MANUAL-VERIFICATION.md's "(likely Sonnet, since Opus tends to respect locked decisions more aggressively)" is dropped rather than rewritten with unverified claims about Fable.
- **Workflow:** branch `btc-00002-fable-model-swap` in a dedicated worktree; squash-merge to main as one commit.
- **This spec's own burndown pass runs the new pairing** (Fable + Opus reviewers, Fable fixer) as a live end-to-end test, per user approval.

## Non-goals

- No changes to agent frontmatter (`model: inherit` stays).
- No fallback/compatibility shims in skill text for pre-2.1.170 builds.
- No Haiku changes (no live skill content dispatches Haiku).
- No upstream (obra/superpowers) PR — this is fork-local work.
