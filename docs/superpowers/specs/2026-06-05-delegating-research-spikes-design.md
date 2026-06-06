# Delegating Research Spikes — Design

**Date:** 2026-06-05
**Status:** Design — in brainstorming
**Skill (proposed):** `delegating-research-spikes`

## 1. Summary

A new orchestrator skill that lets a brainstorming session **delegate a rigorous,
formality-wrapped investigation ("spike") to a background sub-orchestrator** and
fold the distilled findings back into the live brainstorm — without polluting the
host session's context. The host stays interactive with the user; the delegate
runs `writing-plans` + `subagent-driven-development` + `burndown-reviews` in the
background, each handed a single shared **background-delegate profile** that
converts every human-gate in those skills into an **escalation up a reporting
chain** (delegate → host → human). The host's context only ever sees the spike's
distilled report and any genuine escalations — never the dozens of intermediate
subagent transcripts, source reads, or burndown rounds.

It does **not** replace brainstorming. It is a branch brainstorming takes when a
high-risk/unknown design cannot be finalized without deep investigation that
would otherwise blow the host's context window.

## 2. Motivation & steelman

High-risk/unknown brainstorming frequently stalls on unknowns that can only be
resolved by deep work: reading many source files, running a codegen experiment,
scanning real data, adversarially verifying load-bearing claims. Doing that
investigation **inline** blows the host's context window and derails the design
dialogue. The value of this skill is **context economy under deep uncertainty**:
delegate the investigation to a sub-orchestrator that returns only **distilled
findings**, and wrap it in **full superpowers formality** (plan → SDD → burndown
+ code review) so the research is rigorous and committed, not a hand-wave.

This pattern was validated empirically before this skill existed: a manual
delegation of a CP-SAT scheduler de-risk spike (recon → constraint specs →
codegen proof → model-size sanity → snapshot triage, folded back into the design)
produced a markedly better spec/plan, with almost none of the investigation
touching the host context until the final report. Formalizing it makes the
recurring pattern repeatable: **brainstorm hits a wall of unknowns → spin a
rigorous background spike → fold findings back → resume on de-risked ground.**

## 3. De-risk: failure modes & mitigations

These shaped the design; each is addressed below.

| # | Failure mode | Resolution |
|---|---|---|
| 1 | **Durability** — a background delegate's in-process state is lost if the **host process** exits. | Out of scope by constraint: the delegate's lifetime is bounded by the host session's lifetime (accepted). SDD's commit-per-task already persists partial work to git as a side benefit. No **cross-host-exit** resume protocol is in scope. (This is distinct from the within-session escalation resume in §4.4, which continues the delegate via `SendMessage` while the host session is still alive.) |
| 2 | **Human-gate incompatibility** — burndown-reviews pauses on reviewer disagreement / high-escalation-rate; SDD prompts on dirty tree and answers implementer questions; background agents cannot block for input. | **The escalation chain (§4.4).** Every human-gate becomes an escalation routed up the reporting chain via a return/resume cycle, not a local pause. |
| 3 | **Spike spec is a single point of failure** — garbage-in → rigorously-produced garbage-out, discovered late. | The host **brainstorms the spike spec with the user and burns it down on the host** (human present) before dispatch (§4.2). |
| 4 | **Deliverable-type mismatch** — SDD is built for code (TDD/tests/code-quality review); a spike's deliverables are research/specs/analysis. | The background profile **re-points SDD's stages onto research artifacts** (§4.6). |
| 5 | **Cost/runaway + deep nesting** — the real nesting is host → delegate orchestrator → {`writing-plans` (+ plan burndown subagents), SDD (+ per-task subagents + impl burndown subagents)}, roughly **3–4 levels deep**, with autonomous burn. | **The user accepts this cost as bounded** (burndown already round-caps; the authority boundary (§4.7) and spike-spec scope bound the work). **Full burndown is RETAINED** on the internal passes — a `burndown_skip` for the internal passes was considered and **rejected** as contradicting the full-burndown decision. |

## 4. Architecture

### 4.1 Entry — pointer from brainstorming

`brainstorming` gains a small branch (a few-line `REQUIRED SUB-SKILL` pointer):
*if the design hinges on unknowns that need deep investigation before it can be
finalized, invoke `delegating-research-spikes`.* The skill is standalone and
independently testable; brainstorming is otherwise unchanged. The skill may also
be invoked directly by the user.

**When the pointer fires:** the spike is a **mid-brainstorm de-risk branch**,
fired *during* brainstorming's clarifying-questions / design phase — at the
moment the dialogue hits a wall of unknowns — **not** as the terminal transition
out of brainstorming. This must reconcile with brainstorming's hard invariant
("the terminal state is invoking `writing-plans`; the ONLY skill you invoke after
brainstorming is `writing-plans`"). Carve-out: invoking `delegating-research-spikes`
is an *interior* branch of the brainstorm, not its terminal step. The spike runs,
its distilled findings fold back into the live brainstorm, and the brainstorm then
proceeds to its normal terminal state — invoking `writing-plans` — on de-risked
ground. The invariant is preserved: the spike is not the last skill the brainstorm
invokes; `writing-plans` still is.

**Trigger conditions (in the description / pointer):** the design cannot be
finalized without resolving unknowns that require reading/running/verifying more
than fits comfortably in the host context, AND the investigation is separable
from the design dialogue, AND the unknowns are consequential (high-risk/blast
radius) enough to warrant the formality. Not for ordinary brainstorming.

### 4.2 Host-side lifecycle

The host stays interactive with the user throughout:

1. **Frame the spike with the user** — the unknowns to resolve, the deliverables
   (verified answers/specs), the **authority boundary** (§4.7), and the
   escalation policy.
2. **Write the spike spec, plus a minimal `.context.md`.** The spike spec is
   short: unknowns/questions, deliverables, non-goals, authority boundary,
   escalation policy. The host **also writes a minimal spike-spec `.context.md`**
   (unknowns/questions, authority boundary, escalation policy) **before** invoking
   burndown — mirroring `brainstorming`'s checklist step 8, which guards against a
   burndown running with a missing predecessor/context artifact.
3. **Burn down the spike spec on the host** — normal `burndown-reviews`
   (`stage=spec`), human present, with the `.context.md` from step 2 as the
   predecessor context. (Mitigation for risk #3.)
4. **User approves the spike spec.**
5. **Verify a clean tree, then dispatch the background delegate into its own
   worktree.** Before dispatch the host **verifies its own (main) working tree is
   clean** and provisions a **dedicated git worktree** for the spike (per
   `using-git-worktrees`, see §4.3). The two clean-tree checks are distinct: this
   host-side check is on the **host's own tree** at provisioning time; the
   freshly-provisioned spike worktree is **clean by construction** (a new worktree
   off a fresh branch). The worktree is checked out on a **dedicated non-default
   branch** (never main/master), so SDD's per-task commits never land on
   main/master — SDD red-flags starting impl on main/master without user consent, and
   the background delegate has no user to consent. The delegate is dispatched on
   model **opus**. Authoring dynamic
   Workflows for hard leaves is **opted in per `escalating-to-workflows`'s own
   opt-in model** — the skill instruction in the delegate profile constitutes the
   opt-in (with that skill's documented one-time-confirmation fallback if the
   instruction alone is insufficient); no separate harness setting is required. The
   dispatch carries: the burned-down spike spec, the spike-spec `.context.md`, the
   background-delegate profile, the dedicated worktree path, the **escalation-decision
   log path** (§4.4 — the concrete `<date>-<spike>-escalation-log.md` path, initially
   empty), and the escalation contract. The dispatch payload carries this **concrete
   path** so the delegate always references the right log file regardless of the
   naming convention.
6. **Escalation–resume loop** (§4.4) — field escalations until the delegate
   returns `DONE`. The host is **event-driven** here, not hard-blocked: it stays
   interactive with the user between the delegate's returns (§4.3).
7. **Receive the distilled report, own the worktree lifecycle, and fold findings
   into the parent brainstorm.** On `DONE`, the host reads the committed report. The
   delegate has deliberately **not** run `finishing-a-development-branch` (§4.3), so
   the host now decides the spike worktree's fate (merge / keep / discard) — with the
   user, since the host is interactive — and then folds the findings into the parent
   brainstorm, resuming the design on de-risked ground.

### 4.3 The delegate

Runs entirely in the background. It follows a **fixed** path: it invokes the
**existing** skills `writing-plans` (→ a spike plan) then
`subagent-driven-development` (→ executes the plan via its own sub-subagents and,
where warranted, `escalating-to-workflows`) → returns a distilled report. Each
invoked skill is handed the background-delegate profile (§4.5).

**Termination — the delegate does NOT finish the branch.** SDD normally terminates
by invoking `finishing-a-development-branch`, which presents a **human gate** (merge
/ push PR / keep / discard). A background delegate cannot answer that gate, and the
worktree lifecycle is not the delegate's to decide. So the delegate **stops short of
`finishing-a-development-branch`**: it runs SDD's per-task loops, the final review,
and the impl-stage burndown (§4.6), then **exits and returns `DONE`** to the host.
The **host owns the worktree lifecycle** (merge / keep / discard) at fold-back (§4.2
step 7). `finishing-a-development-branch` is on the profile's intercept list (§4.5)
as **do-not-invoke → return `DONE` to host**.

**Worktree ownership & isolation.** The delegate runs in its **own dedicated git
worktree** (provisioned per `using-git-worktrees` in §4.2 step 5, on a **dedicated
non-default branch** so per-task commits never touch main/master), owned
**exclusively** for the spike's duration. The host performs **no git commits** in
that worktree while the delegate runs; the delegate owns all commits there (commit
per task per §4.5). The **one** host write into the worktree is a **filesystem
write** (not a commit): the host writes the `<date>-<spike>-escalation-log.md` file
for the delegate to commit (see the protocol below and §4.4). The files that live in
the delegate's worktree are: the **spike spec** and its **`.context.md`** (written at
provisioning time under the repo's superpowers specs path, §5; read by the delegate as
predecessor context), the spike **plan** and **deliverable doc(s)** the delegate
produces, and the **`<date>-<spike>-escalation-log.md`** (§4.4). The **final distilled report** is written to a
deliverable doc in the worktree and read out by the host when the delegate returns
`DONE` (§4.4) — the host reads the committed report file rather than ingesting
transcripts.

**Escalation-log write/commit protocol (two actors, no contradiction).** The
**host writes** `<date>-<spike>-escalation-log.md` into the worktree **filesystem** on each
escalation resolution — a plain file write, **no git commit by the host**. The
**delegate commits** that file as part of its **next task's commit cycle** (under the
commit-per-task discipline, §4.5). So the "host does not commit into the worktree"
clause holds without exception: the host's only worktree mutation is the filesystem
write of the log; every git commit in the worktree — including the one that captures
`<date>-<spike>-escalation-log.md` — is the delegate's. (See §4.4 for the log's content and §5 for
its location.)

**Host concurrency model.** The delegate runs as a background agent. The host
regains control **at each agent return** — a background agent emits a completion
notification when it returns (`ESCALATION` or `DONE`), and the host converses with
the user at those return points. The host is **not hard-blocked** waiting on the
delegate, but neither does it receive mid-run push interactivity: it acts on the
delegate's state only when the delegate returns. The delegate's model (**opus**) and
its `escalating-to-workflows` opt-in are fixed at dispatch (§4.2 step 5).

**Workflow-escalation safety.** A leaf the delegate escalates to a **dynamic
Workflow** (per `escalating-to-workflows`) runs **to completion and cannot pause or
escalate for input** — a background Workflow has no channel to ask a human mid-run.
Therefore a leaf that could plausibly hit an **above-authority gate**
(`authority-breach`) or a **`spec-ambiguity`** gate **must NOT be escalated to a
Workflow**. The "safe to escalate to a Workflow" criterion is: the leaf is
**self-contained** and contains **no expected human gate** — it can run start-to-finish
on the spike spec's declared authority alone. If a Workflow-escalated leaf
nonetheless hits an unexpected gate, it **fails the leaf and returns a failure**; the
delegate then raises that as an `ESCALATION` to the host (per §4.4) rather than the
Workflow attempting to resolve it.

### 4.4 The escalation chain (reporting-chain model)

A background agent cannot block mid-run waiting for human input, but it can
**terminate with a structured return** and be **resumed later**. In Claude Code
this resume is a real primitive: a background agent (spawned via the Agent tool)
returns an `agentId`, and **`SendMessage` to that `agentId` continues the
previously spawned agent — including a completed background agent — *with its
context intact*** (see the Agent tool / `SendMessage`). So an escalation is a
**return/resume cycle**, like a report syncing with a manager: the delegate
returns `ESCALATION`, the host resolves, and the host calls `SendMessage` to
resume the same delegate with its accumulated context.

**Portability note.** `SendMessage`-style agent resume is Claude-Code-specific.
On platforms **without an agent-resume primitive**, context is **not** "intact"
across the return — the fallback is to **re-dispatch a fresh delegate**, seeded
to reconstruct context from durable state: the **committed worktree state** (the
commit-per-task history, §4.5), the **spike spec + `.context.md`**, and an
**escalation-decision log** (an append-only record of each escalation, its
resolution, and the resumption instruction — a concrete artifact, see below).
Context is thus *reconstructed*, not preserved — the escalation-decision log is what
makes a fresh delegate pick up where the prior one left off.

**Escalation-decision log (concrete artifact).** The log is a real file —
`<date>-<spike>-escalation-log.md` — living **in the delegate's worktree**. The **host writes** it
(a filesystem write) and the **delegate commits** it under the commit-per-task
discipline (§4.5) as part of its next task's commit cycle, so it is durable across a
re-dispatch; the host itself performs no git commit (see §4.3 for the two-actor
protocol). Each time the host (or the human, skip-level) resolves an `ESCALATION`,
the host **appends an entry** to the file — the escalation's `reason`, the question,
the chosen resolution, and the resumption instruction handed back to the delegate —
*before* resuming (via `SendMessage` or re-dispatch); the delegate then commits the
updated log on its next task. It serves a dual purpose: it is the audit trail the
`SendMessage`-resume path carries forward, and it is the durable record the
portability re-dispatch fallback reconstructs context from. It is listed in the
dispatch payload (§4.2 step 5), the worktree file enumeration (§4.3), and the file
layout (§5).

Three rungs:

```
human ── (skip-level) ── host orchestrator ── (manager) ── delegate orchestrator ── per-task subagents
       ▲                                     ▲                                     ▲
       │ host→human edge:                    │ delegate→host edge:                 │ subagent→delegate edge:
       │ AskUserQuestion (skip-level),       │ ESCALATION return, then             │ normal SDD BLOCKED /
       │ only when host can't decide         │ SendMessage resume of delegate      │ approach-fork; delegate
       │                                     │                                     │ resolves in-band
```

Each edge carries exactly one behavior: the subagent→delegate edge is in-band SDD
handling; the delegate→host edge is an `ESCALATION` return followed by a
`SendMessage` resume; the host→human edge is an `AskUserQuestion` skip-level prompt
raised only when the host cannot decide on its own.

- Per-task subagents escalate to the delegate orchestrator (normal SDD `BLOCKED`
  / approach-fork handling — the delegate resolves what it can in-band).
- The delegate escalates to the **host** by returning `status=ESCALATION` with a
  structured ask. The host resolves it if it can, or **bubbles to the human
  (skip-level)** via `AskUserQuestion`, then **resumes the delegate** with the
  decision (via `SendMessage`, or via the re-dispatch fallback on platforms
  without resume — see above).

**Escalation batching (resolved).** The delegate **batches** all escalations
reached at a natural checkpoint into a **single** `ESCALATION` return, rather than
escalating one at a time. One-at-a-time round-trips multiply the return/resume cost
(and, on the fallback path, multiply context-reconstruction cost). Between
escalation-worthy points, the delegate **continues autonomous work past any
escalation it can safely defer**, accumulating the batch; it returns the batch when
it reaches a checkpoint where it can make no further confident progress. (This
resolves the former §8 open question.)

**Authority-breach is the exception — never batched or deferred.** Continuing past
an authority violation is *itself* a violation, so an `authority-breach` causes an
**immediate single-item `ESCALATION` return** the moment it is reached — the delegate
does not accumulate further work or fold other deferred items into it. All other
`reason` types follow the normal batch-at-checkpoint rule above.

**Resume after a dirty-tree authority-breach.** When the host resumes the delegate
after resolving a dirty-tree `authority-breach` (the SDD pre-flight case, §4.5), the
delegate **re-runs SDD's full pre-flight** — the clean-tree check and `diff_base`
capture — before dispatching any task, rather than jumping into the middle of SDD.
This guarantees the tree state and diff base the rest of the run depends on are
re-established under the resumed (now-clean) conditions.

**Escalation return schema:**

```
status:         ESCALATION
escalations:    [ {                         # one or more, batched per above
  reason:         unresolvable-reviewer-disagreement | blocked-task | approach-fork | spec-ambiguity | authority-breach
  question:       <the decision needed, plain language>
  options:        [<option + tradeoff>, ...]
  recommendation: <delegate's pick + why>
  context:        <minimal context the host needs to decide>
}, ... ]
progress:       <tasks done, commits so far>
```

The `unresolvable-reviewer-disagreement` reason (the burndown step-D case) is
reserved for **genuine** can't-determine-if-the-reviewer-is-right cases: before
escalating with this reason the delegate **must exhaust Accept / Override** — it
escalates only when it cannot decide whether the reviewer is correct, not merely
because it disagrees.

The delegate's terminal `status=DONE` return carries the distilled findings
report (the only large payload the host ingests).

### 4.5 The background-delegate profile (shared override doc)

A single doc (`background-delegate-profile.md`).

**Injection + precedence.** The profile is **prepended to the delegate
orchestrator's dispatch prompt** (`delegate-prompt.md`). It is the **delegate
orchestrator** — not the host — that invokes `writing-plans`, `subagent-driven-development`,
and `burndown-reviews`. Handing a doc *alongside* an invoked skill does not change
that skill's own text; so the precedence contract is enforced by the **delegate
orchestrator**, which is instructed to treat the profile as **OVERRIDING** any
"pause / ask the user / block until resolved" instruction in the skills it invokes.
When an invoked skill would block for human input, the delegate orchestrator does
not honor that block — it converts it to an `ESCALATION` return per §4.4.

**Control-flow points the profile intercepts.** The delegate orchestrator enforces
the override at exactly these points, with these per-gate decisions:

- **`writing-plans` Execution Handoff choice** → **default to subagent-driven-development**
  (do not prompt the user for the handoff mode).
- **`writing-plans` ambiguities** → escalate (`spec-ambiguity`) only for substantive
  scope/approach forks; resolve anything clearly within the spike spec's authority.
- **`writing-plans` Scope Check prompt** (which can ask the user to decompose the
  spec into sub-projects) → **suppress**: the spike spec's scope was already bounded
  during the host-side spike-spec burndown (§4.2 step 3), so the delegate treats it as
  appropriately scoped and proceeds without prompting.
- **`writing-plans` `stage=plan` burndown step-B (high-escalation-rate) pause** →
  same conversion as the deliverable burndown's step-B below (auto-select (a),
  suppress (b)/(c), note the occurrence).
- **`writing-plans` `stage=plan` burndown step-D (reviewer disagreement)** → escalate
  with `reason=unresolvable-reviewer-disagreement`, **only after exhausting
  Accept/Override** (§4.4) — same conversion as the deliverable burndown's step-D
  below.
- **SDD Pre-flight dirty-tree prompt** → **escalate** (`authority-breach` — a dirty
  tree in the dedicated worktree is unexpected and outside the delegate's authority
  to resolve); **do not prompt**. (On resume, the delegate re-runs SDD's full
  pre-flight, §4.4.)
- **SDD implementer questions / `BLOCKED` / approach forks** → resolve in-band where
  within authority; otherwise escalate (`blocked-task` / `approach-fork`).
- **`finishing-a-development-branch`** → **do not invoke; return `DONE` to host**
  (the host owns the worktree lifecycle, §4.2 step 7 / §4.3).
- **`burndown-reviews` step D (reviewer disagreement)** (both the `stage=plan` and the
  deliverable burndown) → escalate with `reason=unresolvable-reviewer-disagreement`,
  **only after exhausting Accept/Override** (§4.4).
- **`burndown-reviews` step B high-escalation-rate pause** (both burndowns) →
  **auto-select option (a) "skip remaining escalations this round as confident
  overrides" without prompting**, and **note that it occurred** in the next
  `ESCALATION` / `DONE` return so the host/human can audit it. The delegate
  **suppresses options (b) abort and (c) keep-going entirely** — it does not surface
  them. This is a *only-reachable choice*, not merely a default: (a) is the single
  branch the delegate can take.
- **`burndown-reviews` terminal residual prompt** — the "N rounds didn't converge …
  Accept as-is / run more rounds / fix manually?" residual prompt that burndown
  raises when its round cap is hit without convergence (both the `stage=plan` and the
  deliverable burndown) → **escalate** with
  `reason=unresolvable-reviewer-disagreement`, carrying the **residual finding list**
  in `context`; **do not prompt the user directly**. This is a third class of
  blocking human gate beyond step-B and step-D.
- **`burndown-reviews` fatal abort (`hard_escalate-with-abort`)** — the fatal-abort
  terminal outcome (both burndowns) → **escalate** with a fatal-abort reason
  (`reason=blocked-task`), carrying the **abort error** in `context`; **do not
  surface it to the user directly**. Like the residual-non-converged prompt, this is
  a blocking terminal gate the delegate must convert to an `ESCALATION` return rather
  than handle locally.

**Never `burndown_skip`.** Across every intercepted burndown — the host-side spike-spec
burndown is the user's, but every *internal* delegate burndown (`writing-plans`
`stage=plan` and the deliverable burndown) — the delegate **never sets
`burndown_skip`**: full burndown is retained on all internal passes, per the
full-burndown decision (risk #5).

Common rules across these points:

- **"You are a background delegate; you cannot pause for human input."**
- **Prefer confident Override; reserve Escalate for genuine uncertainty.**
  Auto-resolve anything clearly within the spike spec's authority; escalate only
  above-authority / ambiguous / irreversible decisions. (The burndown
  Accept/Override/Escalate judge is unchanged — only the *endpoint* of "Escalate"
  moves from local-human-pause to the reporting chain.)
- **Commit per task** (durable progress; also satisfies risk #1's side benefit and
  feeds the fallback-path context reconstruction, §4.4).

### 4.6 Deliverable mapping (research SDD)

The profile re-points SDD's code-centric stages onto research artifacts. The
**research SDD reuses SDD's existing prompt templates, adapted for documents**
(deliverable docs in place of code, acceptance checks in place of failing tests) —
it does not fork SDD:

| SDD stage | Research-spike meaning |
|---|---|
| "failing test" written first | an explicit **acceptance check** on the deliverable doc (required sections present, citations verified, claims sourced) |
| implementer | an **investigator** subagent producing the deliverable doc |
| spec-compliance review | does the doc **answer the spike spec's question** (no more, no less) |
| code-quality review | is the finding **rigorous, sourced, adversarially checked** |

**Final burndown pass on the deliverable.** SDD's native terminal burndown runs
**`stage=impl`** over the deliverable docs (the `diff_paths` SDD collects), and the
research SDD keeps it that way — **SDD is not forked**, so its terminal burndown stays
hardwired to `stage=impl` with predecessor `{plan_path, diff_base, diff_paths}`.
Re-pointing that terminal pass to `stage=spec` was considered and **rejected**: it
would contradict "reuses SDD's templates / does not fork SDD" (SDD hardwires the
stage and the predecessor shape), and `stage=spec` has no `diff_base`/`diff_paths`
predecessor to hand it.

Instead, the deliverable-type adaptation is carried by the **background-delegate
profile**, not by a stage swap: the profile instructs the impl-stage **reviewers AND
the fixer** that the "implementation" under review is **research documents**. They
evaluate **rigor, sourcing / citations, completeness, and answers-the-spike-question**
— **not** code concerns (no tests, error-handling, regressions, or runtime-behavior
findings). The burndown's **diff-based file collection works for markdown deliverables**
unchanged: SDD collects the changed deliverable docs as `diff_paths` against the
captured `diff_base` exactly as it would code files; only the *evaluation lens* is
re-pointed onto documents.

**Research lens reaches the implementer too — not just reviewers/fixer.** The
impl-stage **reviewers and fixer** receive the research lens (above), but SDD's
**implementer** subagent is dispatched by SDD directly and its `implementer-prompt.md`
is hardwired for code/TDD — so handing the profile alongside SDD does not, by itself,
re-point the implementer. The delegate orchestrator therefore **injects a
research-mode preamble/context into the per-task prompt it constructs for each
implementer dispatch**, consistent with SDD's "controller provides full task text +
context" model. The preamble re-points the implementer to **produce/verify a research
document** (deliverable doc satisfying the acceptance check, citations sourced and
adversarially checked) **rather than writing code + tests**. Without this injection
the implementer would default to its hardwired code/TDD behavior.

**Empty-`diff_paths` short-circuit is a failure, not a clean DONE.** SDD's Burndown
Review Pass has an **empty-`diff_paths` short-circuit**: if nothing changed since
`diff_base`, it skips the burndown and proceeds. For a spike this is degenerate — it
would skip the only quality gate and return `DONE` with **no actual deliverable**.
So an empty-`diff_paths` SDD outcome is **NOT** treated as a clean `DONE`: the
delegate instead returns `ESCALATION` (`reason=blocked-task`, "no deliverable
produced"). To make the deliverable reliably appear in `diff_paths`, the profile adds
a rule that **deliverable docs MUST be committed under the commit-per-task discipline**
(§4.5) so they show up in the diff against `diff_base`.

### 4.7 Authority boundary & safety

The spike spec declares the delegate's authority explicitly. Default:
**investigation-only** — gather, run throwaway experiments, verify, and *write
deliverable docs*; do **not** take irreversible or outward-facing actions
(no pushes, no deploys, no destructive ops, no production changes). Any action
beyond the declared boundary is an `authority-breach` escalation. Throwaway
experiments (e.g. codegen proofs) run in isolation and are not committed unless
the spec says so.

## 5. Skill file layout + brainstorming edit

```
skills/
  delegating-research-spikes/
    SKILL.md                        # orchestrator: lifecycle, escalation chain, dispatch (host-side)
    background-delegate-profile.md  # the shared override doc handed to every delegated subskill
    delegate-prompt.md              # template for dispatching the background delegate orchestrator
  brainstorming/
    SKILL.md                        # + a few-line REQUIRED-SUB-SKILL pointer to delegating-research-spikes
```

`SKILL.md` description follows CSO: triggering conditions only, no workflow
summary (per `writing-skills`). Cross-references use `**REQUIRED SUB-SKILL:**`
markers, not `@`-links.

**Artifact write path.** The delegate writes its spike spec / plan / deliverable
artifacts to the **repo's superpowers specs/plans path**. When running inside the
olympus repo this **honors the `btc-superpowers-paths` override** —
`experimental/btc/superpowers/` rather than the default `docs/superpowers/` — so the
spike's specs and plans land under the override location alongside other
btc-superpowers artifacts.

**Per-spike worktree files.** Inside the delegate's dedicated worktree (provisioned
in §4.2 step 5), the per-spike runtime artifacts are:

```
<superpowers specs/plans path>/
  <date>-<spike>-spec.md            # spike spec (host-written at provisioning)
  <date>-<spike>-spec.context.md    # spike-spec .context.md (host-written)
  <date>-<spike>-plan.md            # spike plan (delegate-written, writing-plans)
  <date>-<spike>-deliverable*.md       # deliverable doc(s) + final distilled report
  <date>-<spike>-escalation-log.md     # escalation-decision log: host-written (filesystem), delegate-committed (§4.4)
```

The escalation-decision log follows the sibling artifact naming convention —
`<date>-<spike>-escalation-log.md` — for consistency and archival clarity alongside
the spec / plan / deliverable files (it is per-worktree, so this is about naming
consistency, not collision avoidance). It is **written by the host** (filesystem) and
**committed by the delegate** under the commit-per-task discipline (§4.3, §4.5); it is
the durable record both the `SendMessage`-resume context and the portability
re-dispatch fallback rely on (§4.4). Because the §4.2 dispatch payload carries the
**concrete path**, the delegate always references the right file regardless of the
naming convention.

## 6. Testing approach (writing-skills TDD)

Per `writing-skills`' Iron Law, the skill is built test-first. RED pressure
scenarios (baseline, without the skill) target the specific failure modes:

- A background delegate that **wrongly pauses for human input** (should escalate
  via return instead).
- A delegate that **escalates everything** (should prefer confident Override).
- A delegate that **auto-resolves an above-authority / irreversible call**
  (should escalate `authority-breach`).
- A delegate that **lets intermediate transcripts leak into the host** (should
  return only the distilled report).
- A host that **dispatches without burning down the spike spec** (skips risk-#3
  mitigation).
- A delegate that hits **two non-authority escalations and one `authority-breach`**
  in a run (escalation-batching pressure). Passing behavior: **one immediate
  single-item return for the `authority-breach`** (never batched or deferred, §4.4)
  **plus one batched return for the two deferred non-authority items** at the next
  checkpoint — not three separate returns, and not one batch of three.

Alongside the RED failure scenarios, a **happy-path host-lifecycle scenario**
exercises the full intended flow end-to-end: the host **frames the spike spec with
the user → burns it down on the host (`stage=spec`) → verifies a clean tree and
dispatches the delegate into its dedicated worktree → receives `DONE` with the
distilled report → folds findings back into the parent brainstorm** — confirming
the lifecycle (§4.2) works when nothing goes wrong, not only that the failure modes
are caught.

An **escalation→resume scenario** exercises the return/resume path (§4.4)
specifically: the delegate returns **one** `ESCALATION`; the host **appends the
resolution** to the `<date>-<spike>-escalation-log.md` and **resumes the delegate via
`SendMessage`**. Passing behavior: the **resumed delegate picks up the accumulated
context** — it commits the appended log on its next task and continues — then makes
further progress and **eventually returns `DONE`**. This is distinct from the
happy-path scenario (which reaches `DONE` with **no** escalation) and from the
escalation-batching scenario (which checks the *return structure* — one immediate
authority-breach return plus one batched return — but not the resume side).

Watch baseline failure, write the skill to pass, refactor to close loopholes.

## 7. Scope / non-goals

**In scope:** the orchestrator skill, the shared background profile, the delegate
dispatch template, the brainstorming pointer, and the test scenarios.

**Non-goals:**
- A durability/resume protocol for delegates surviving host-process exit (risk #1;
  out of scope by constraint).
- Forking variant copies of writing-plans / SDD / burndown (rejected in favor of
  the shared profile).
- Changing the existing skills' bodies beyond the brainstorming pointer.
- Server-side / remote / cron execution of the delegate.

## 8. Open questions

- **Skill name** — `delegating-research-spikes` is the working name; alternatives
  welcome (`delegated-spike`, `research-spike-delegation`).
- **Profile reuse breadth** — whether the background profile is general enough to
  later support delegated work *outside* brainstorming (e.g. a delegated debug
  spike). Designed to be reusable, but only the brainstorming entry is in scope now.

(Escalation batching, formerly listed here, is now resolved in §4.4: the delegate
batches escalations reached at a natural checkpoint into one `ESCALATION` return.)
