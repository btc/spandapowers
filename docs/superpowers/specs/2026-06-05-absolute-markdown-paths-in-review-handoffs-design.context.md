# Context — absolute markdown paths in review handoffs

## User's original request

> "i'd like all markdown paths to be absolute for all skills in this project
> where the agent is giving me markdown to review. this way i can always open it
> in cmux easily. let's find the spots and spec and plan and execute the 'code'
> changes. and commit. maybe do it in a worktree to not stomp other in flight
> PRs on spandapowers"

The user opens the reported markdown path in cmux; a relative path is not
directly openable, so they want absolute paths in the handoff messages.

## Locked-in design decisions

- **Scope = exactly two handoffs:** the `brainstorming` spec review gate and the
  `writing-plans` execution handoff. (User chose "Just those two gates" over the
  broader options.)
- **Mechanism = inline instruction, no committed bash script.** The user asked
  "should we commit a bash script in spandapowers? overkill?" — agreed it is
  overkill. Use the existing inline `git rev-parse --show-toplevel` idiom to
  prefix the repo-relative path.
- **Worktree:** do the work in a git worktree (created at
  `/Users/btc/src/spandapowers-abs-md-paths`) to avoid disturbing the in-flight
  `delegating-research-spikes` branch.
- **Commit target:** land commits on `main` directly ("yes just commit it to
  main precisely").

## Explicit non-goals

- Do NOT change internal save-to templates (where to *write* a file); they stay
  repo-relative.
- Do NOT touch other skills (executing-plans, subagent-driven-development,
  requesting-code-review, burndown-reviews) — none hand the user a markdown file
  to open and review.
- Do NOT add a script or any dependency.
- Not destined for an upstream PR; fork-local workflow change.
