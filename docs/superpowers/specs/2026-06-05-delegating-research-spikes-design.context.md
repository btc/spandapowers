# Context — Delegating Research Spikes

## Original request

> Create a skill in spandapowers that formalizes the "subagent spike during
> brainstorming" pattern: the host session/agent defines the initial spike spec,
> then the burndown + planning + SDD all happen in the background (delegated to a
> sub-orchestrator) — a clever way to avoid polluting host context while still
> getting quality research done. This is going to become part of high-risk/unknown
> brainstorming. Steelman and de-risk the endeavor.

Originated from an in-flight manual instance of the pattern (a CP-SAT scheduler
de-risk spike delegated to a background Opus orchestrator), which worked well and
motivated formalizing it.

## Locked-in design decisions

- **Autonomy = escalation chain**, not fire-and-forget or block-and-wait. A
  background agent can't pause for input, so a human-gate becomes a return/resume
  cycle: delegate returns `status=ESCALATION` → host resolves or bubbles to the
  human (skip-level) → resumes the delegate via `SendMessage`. Org-reporting model.
- **One orchestrator skill + one shared `background-delegate-profile.md`**; the
  existing skills (writing-plans, SDD, burndown-reviews) are unchanged. Rejected:
  forked variant skills, and a `mode=background` parameter on the existing skills.
- The only background-mode change is uniform: **every human-gate → escalate up
  the chain** (burndown's "Escalate" endpoint moves from local-human-pause to the
  reporting chain; the Accept/Override/Escalate judge itself is unchanged).
- **Entry = standalone skill + a small pointer from brainstorming** (not woven in,
  not user-invoke-only).
- **Host burns down the spike spec (human present) before dispatch** — the spike
  spec is the single point of failure.
- **Durability is out of scope by constraint** — the delegate's lifetime is
  bounded by the host session; SDD's commit-per-task persists partial work as a
  side benefit. No resume protocol.
- **Deliverable mapping**: SDD's code-centric stages re-point onto research
  artifacts (acceptance check on the doc; investigator; answers-the-question
  review; rigorous-and-sourced review).
- **Authority boundary = investigation-only by default**; out-of-boundary actions
  are an `authority-breach` escalation.
- Built **test-first** per writing-skills (RED pressure scenarios for the named
  failure modes).
- Cost/runaway and the extra nesting level accepted as bounded.

## Explicit non-goals

- A durability/resume protocol for delegates surviving host-process exit.
- Forked variant copies of writing-plans / SDD / burndown.
- A `mode=background` parameter on the existing skills.
- Server-side / remote / cron execution of the delegate.
- Changing the existing skills' bodies beyond the brainstorming pointer.
