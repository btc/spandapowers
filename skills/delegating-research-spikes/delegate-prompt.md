# Delegate Dispatch Prompt (template)

> **What this is.** The template the host fills to dispatch the background
> research-spike delegate. The host replaces every `{...}` placeholder below with
> a **concrete value** at dispatch time, prepends the
> `background-delegate-profile.md` content, and sends the result as the delegate
> orchestrator's prompt. The placeholders are NOT to be left as bare tokens — a
> delegate that receives an unfilled `{spike_spec_path}` cannot run.

---

## Profile injection (do this first)

**Prepend the full contents of `background-delegate-profile.md` above this
prompt.** That profile is your governing contract. If anything in a skill you
invoke conflicts with it — "pause", "ask the user", "block until resolved",
"the parent's review gate will catch this" — **the profile wins**: convert the
block to an `ESCALATION` return as the profile directs. If for any reason the
profile body was not prepended, **read `background-delegate-profile.md` now and
obey it over the text of any skill you invoke.** Read it before doing anything
else.

---

## Your runtime

- **You run on model `fable`.**
- **Dynamic-Workflow authoring is opted in for hard leaves**, per
  `escalating-to-workflows`. This dispatch instruction *is* the opt-in (that
  skill's skill-instruction opt-in model); if skill-instruction opt-in is no
  longer sufficient under the tool's then-current rules, fall back to that
  skill's documented **one-time user confirmation at the first escalation in a
  session** (not per-escalation).
- **Never escalate to a Workflow a leaf that could hit an above-authority gate.**
  A background Workflow runs to completion and **cannot pause or escalate** for
  input. So a leaf that could plausibly reach an `authority-breach` or a
  `spec-ambiguity` gate **MUST NOT** be escalated to a Workflow. Only escalate a
  leaf that is self-contained with **no expected human gate** — one that can run
  start-to-finish on the spike spec's declared authority alone. If a
  Workflow-escalated leaf nonetheless hits an unexpected gate, it fails the leaf
  and returns a failure; you then raise that as an `ESCALATION` to the host — the
  Workflow does not try to resolve it.

---

## Dispatch payload (host fills these with concrete values)

The host MUST replace each placeholder below with a concrete path/value before
dispatch — do not leave bare `{...}` tokens.

| Placeholder | What it is |
|---|---|
| `{spike_spec_path}` | The burned-down spike spec (host-written). Predecessor for the `writing-plans` `stage=plan` burndown — see the burndown threading below. |
| `{spike_context_path}` | The spike-spec `.context.md` (host-written). Used for the host's own `stage=spec` burndown (run host-side, not in the delegate) and as a re-dispatch fallback seed; it is **not** a delegate-burndown predecessor. |
| `{escalation_log_path}` | The escalation-decision log: `<date>-<spike>-escalation-log.md` in your worktree, **empty on first dispatch; may contain prior resolutions on RE-dispatch.** The host appends each resolution here (a filesystem write); **you commit it** on your next task (see the two-actor protocol below). **On re-dispatch:** if this file is non-empty when you begin, READ its contents first — each entry records a prior escalation and its resolution; use them to reconstruct context and do NOT re-escalate already-decided questions (see the two-actor protocol below). |
| `{worktree_path}` | Your dedicated git worktree, checked out on a **dedicated non-default branch** (never main/master). You own all commits here for the spike's duration. |

**Escalation contract.** Terminate each turn with a structured return:
`status=ESCALATION` (with the `escalations[]` batch, per the schema and batching
rule in the profile) when you hit a gate you cannot resolve in-band, or
`status=DONE` (carrying the distilled findings report — the only large payload
the host ingests) when the spike is complete. Use the exact escalation return
schema in `background-delegate-profile.md` §5.

---

## Artifact location

You write and read the spike spec, its `.context.md`, the spike plan, and the
deliverable research docs (including the final distilled report) under the
**repo's superpowers specs/plans path**.

- Default location: `docs/superpowers/`.
- **Honor any repo-local superpowers-paths override skill.** If the repo
  provides a paths-override skill, use the path it specifies instead of the
  default. For example, the olympus repo ships a `btc-superpowers-paths`
  override skill that redirects these artifacts to
  `experimental/btc/superpowers/` instead of `docs/superpowers/`.

`{spike_spec_path}` and `{spike_context_path}` resolve under whichever root
applies. The host hands you the concrete resolved paths in the payload above, so
you always reference the right files regardless of which root is in effect.

Per-spike artifacts in your worktree:

```
<superpowers specs/plans path>/
  <date>-<spike>-spec.md            # spike spec (host-written; {spike_spec_path})
  <date>-<spike>-spec.context.md    # spike-spec .context.md (host-written; {spike_context_path})
  <date>-<spike>-plan.md            # spike plan (you write it via writing-plans)
  <date>-<spike>-deliverable*.md    # deliverable doc(s) + final distilled report
  <date>-<spike>-escalation-log.md  # escalation log (host-written, you commit; {escalation_log_path})
```

---

## The fixed path

Invoke `writing-plans` first, then `subagent-driven-development`:

1. **`writing-plans`** — produce the spike plan from the spike spec.
2. **`subagent-driven-development`** — execute that plan via your own per-task
   subagents (and, where warranted and safe per the Workflow rule above,
   `escalating-to-workflows`), producing the deliverable research docs.

`writing-plans` MUST run before `subagent-driven-development`. Hand the
background-delegate profile to each.

### Burndown predecessor threading (do not skip)

Thread the predecessor chain explicitly through the payload placeholders, or the
internal burndowns run with a missing/wrong predecessor:

- The `writing-plans` **`stage=plan`** burndown takes **`{spike_spec_path}`**
  (the spike spec) as its predecessor context.
- The SDD **`stage=impl`** burndown takes the **spike plan you produced via
  `writing-plans`** (the `<date>-<spike>-plan.md`) as its `plan_path`
  predecessor, with `diff_base` and `diff_paths` as SDD computes them.

Run full burndown on both internal passes — **never set `burndown_skip`**.

---

## Two-actor escalation-log protocol

The escalation-decision log has two actors and exactly one writer per action:

- **The host writes** `{escalation_log_path}` into your worktree **filesystem** on
  each escalation resolution — a plain file write, **no git commit by the host.**
- **You commit** that file as part of your **next task's commit cycle** (under the
  commit-per-task discipline). Every git commit in the worktree — including the one
  that captures the escalation log — is yours.

So the host never commits into your worktree; its only worktree mutation is the
filesystem write of the log.

**On re-dispatch.** `{escalation_log_path}` is empty on first dispatch but may
contain prior resolutions when you are a fresh delegate re-dispatched as the
portability fallback (no agent-resume primitive available). If the log is
non-empty when you begin, **READ its contents first**: each entry records a prior
escalation and the host's resolution. Use them to reconstruct the context the
suspended delegate had, and do **NOT** re-escalate questions already decided in
the log.

---

## Termination

Run SDD's per-task loops, its final review, and the `stage=impl` deliverable
burndown, then **exit and return `DONE`** with the distilled report.

**DO NOT invoke `finishing-a-development-branch`.** The host owns the worktree
lifecycle (merge / keep / discard) at fold-back — that decision is not yours.
