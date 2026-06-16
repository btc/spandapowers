---
name: delegating-research-spikes
description: Use when a brainstorm or design hinges on consequential unknowns that can only be resolved by deep investigation — reading, running, or verifying more than fits comfortably in the host context — and that investigation is separable from the design dialogue. Not for ordinary brainstorming.
---

# Delegating Research Spikes

## Overview

**Core principle: context economy under deep uncertainty.** When a high-risk
design stalls on unknowns that need rigorous investigation, delegate that
investigation — a "spike" — to a **background sub-orchestrator** that returns
only **distilled findings**, never the dozens of intermediate transcripts,
source reads, or burndown rounds. The host stays interactive with the user; the
delegate runs full superpowers formality (plan → SDD → burndown) in the
background. Human-gates inside those skills become **escalations up a reporting
chain** (delegate → host → human), since a background agent cannot block for
input.

This does **not** replace brainstorming. It is an *interior* branch a brainstorm
takes mid-dialogue to de-risk; the brainstorm then resumes and proceeds to its
normal `writing-plans` terminal on de-risked ground.

## When to use

All three must hold (else stay in ordinary brainstorming):

1. The design **cannot be finalized** without resolving the unknowns.
2. Resolving them needs **reading/running/verifying more than fits** the host context.
3. The unknowns are **consequential** (high blast radius) enough to warrant the formality.

AND the investigation is **separable** from the design dialogue.

**NOT for:** ordinary brainstorming, quick lookups, or anything that fits inline.

## Host lifecycle

The host stays interactive with the user throughout. In order:

1. **Frame the spike with the user** — the unknowns, the deliverables (verified
   answers/specs), the authority boundary, the escalation policy.
2. **Write the spike spec** (short: unknowns, deliverables, non-goals, authority
   boundary, escalation policy), **then write the spike-spec `.context.md`
   BEFORE the host burndown, and pass it as the burndown predecessor** (mirrors
   brainstorming's checklist step 8).
3. **Burn down the spike spec on the host** — `burndown-reviews` with
   `stage=spec`, human present, `.context.md` from step 2 as predecessor.
4. **User approves the spike spec.**
5. **Verify a clean tree, then provision a dedicated worktree and dispatch.**
   First verify the host's **own** working tree is clean; then provision a
   dedicated worktree on a **non-default branch** (never main/master, so the
   delegate's per-task commits never land on main/master — SDD red-flags impl on
   main/master and the delegate has no user to consent). Dispatch the delegate on
   model **opus** using `delegate-prompt.md`, doing two distinct things:
   **(a) PREPEND** the full `background-delegate-profile.md` contents above the
   prompt; **(b) FILL** the four `{...}` placeholders with concrete values —
   `{spike_spec_path}` (the burned-down spike spec), `{spike_context_path}` (the
   spike-spec `.context.md`), `{escalation_log_path}` (the concrete
   `<date>-<spike>-escalation-log.md`, initially empty), and `{worktree_path}`.
   The profile is prepended, not a placeholder.
6. **Event-driven escalation/resume loop** (below) — field escalations until the
   delegate returns `DONE`. The host is **not hard-blocked**; it stays
   interactive with the user and acts on the delegate only at each return.
7. **Receive `DONE`, own the worktree lifecycle, fold findings back.** Read the
   committed distilled report. The delegate did **not** run
   `finishing-a-development-branch`, so the host now decides the worktree's fate
   (merge / keep / discard) with the user, folds the findings into the parent
   brainstorm, and the brainstorm proceeds to its normal `writing-plans` terminal.

## Escalation chain

Three rungs (read left → right, escalation flows up the chain):

```
per-task subagents ──(subagent→delegate)── delegate orchestrator ──(delegate→host)── host orchestrator ──(host→human)── human
```

- **subagent → delegate:** normal SDD `BLOCKED` / approach-fork; the delegate
  resolves in-band.
- **delegate → host:** the delegate returns `status=ESCALATION` with a
  structured ask. The host resolves it, or **bubbles to the human (skip-level)**
  via `AskUserQuestion`, then **resumes the same delegate via `SendMessage`**
  with its context intact.
- **host → human:** `AskUserQuestion`, raised **only when the host cannot decide**.

**Resume primitive & portability fallback.** `SendMessage` to the delegate's
`agentId` continues it with context intact. On platforms **without** an
agent-resume primitive, the fallback is to **re-dispatch a fresh delegate**
seeded from durable state — the committed worktree, the spike spec + `.context.md`,
and the escalation log — which *reconstructs* (not preserves) context.

**Escalation schema and the full gate-intercept list live in the profile —
do not duplicate them here.**

**REQUIRED BACKGROUND:** Read `background-delegate-profile.md` — for the
`status=ESCALATION` schema, the `reason` enum, the batching rule, and every
intercepted human-gate.

**Two-actor escalation-log protocol.** On each resolution the host **appends** to
`<date>-<spike>-escalation-log.md` in the worktree — a **filesystem write, no git
commit by the host** — *before* resuming. The **delegate commits** that file on
its next task under the commit-per-task discipline. The host's only worktree
mutation is the filesystem write; every commit in the worktree is the delegate's.

## References

- **REQUIRED BACKGROUND:** Read `background-delegate-profile.md` — the delegate's override doc (a local file, not an invocable skill).
- **REQUIRED BACKGROUND:** Read `delegate-prompt.md` — the dispatch template (a local file, not an invocable skill).
- **REQUIRED SUB-SKILL:** `burndown-reviews` — the host's `stage=spec` spike-spec
  burndown (step 3).

## Authority boundary

The spike spec declares the delegate's authority explicitly. Default:
**investigation-only** — gather, run throwaway experiments, verify, and write
deliverable docs; do **not** take irreversible or outward-facing actions (no
pushes, deploys, destructive ops, or production changes). Any action beyond the
declared boundary is an `authority-breach` escalation.

## Host-side rationalization table

Excuses observed in host-side baselines (S5, S7, S8) — and the reality that
closes each. If you catch yourself reaching for the left column, the right column
is the rule.

| Rationalization | Reality |
|---|---|
| "The user is eager — just dispatch the delegate now." | The host `stage=spec` spike-spec burndown is a **hard prerequisite**. Burn down the spec (and get user approval) *before* any dispatch. Eagerness does not skip the gate. |
| "I wrote a `writing-plans` plan and ran a `stage=plan` burndown — that's the spec burndown." | No. The host burndown is `burndown-reviews` **`stage=spec`** over the **spike spec**, with the spike-spec `.context.md` as predecessor. A `stage=plan` burndown on a plan is a different gate the *delegate* runs later — not the host's spec burndown. |
| "I'll skip the `.context.md` and just burn down the spec." | The `.context.md` is the burndown **predecessor** and MUST exist *before* the burndown runs (mirrors brainstorming step 8). No predecessor → reviewer dispatch silently fails. Write it first. |
| "Just dispatch in the current workspace / on the default branch." | Dispatch only after verifying the host tree is clean **and** provisioning a dedicated worktree on a **non-default branch**. The delegate's per-task commits must never land on main/master. |
| "The delegate escalated — I'll block and wait for it like a burndown step-D pause." | The host is **not hard-blocked**. It stays interactive with the user, resolves the escalation (or bubbles to the human via `AskUserQuestion`), and **resumes the delegate via `SendMessage`**. There is no in-process blocking pause. |
| "I'll commit the escalation log into the worktree myself." | The host's **only** worktree mutation is a **filesystem write** of the escalation log — **no host git commit**. The **delegate** commits it on its next task. Every commit in the worktree is the delegate's. |
| "The delegate is done — the spike's findings are the terminal output." | The spike is an **interior** branch. After fold-back the brainstorm **still proceeds to `writing-plans`**. Do not treat the spike as terminal; do not skip `writing-plans`. |
| "Let the delegate run `finishing-a-development-branch` to wrap up the worktree." | The delegate returns `DONE` and does **not** run `finishing-a-development-branch`. The **host** owns the worktree lifecycle (merge / keep / discard) with the user at fold-back. |

## Red Flags — STOP (host-side)

If any of these is about to happen, STOP and take the mapped action:

- **About to dispatch the delegate before the host `stage=spec` burndown + user approval** → burn down the spike spec first, then approve, then dispatch.
- **About to dispatch without a `.context.md` predecessor** → write the spike-spec `.context.md` first; it must exist before the burndown.
- **About to dispatch on the default branch / dirty tree / current workspace** → verify a clean tree and provision a dedicated **non-default-branch** worktree first.
- **About to block-and-wait on a delegate escalation** → resolve (or bubble to the human via `AskUserQuestion`) and **resume via `SendMessage`**; the host never hard-blocks.
- **About to `git commit` into the delegate's worktree (e.g. the escalation log)** → only **filesystem-write** the log; the delegate commits it.
- **About to treat the spike findings as the terminal / skip `writing-plans`** → fold findings into the brainstorm and proceed to `writing-plans`.
