---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - creates isolated git worktrees with smart directory selection and safety verification
---

# Using Git Worktrees

## Overview

Git worktrees create isolated workspaces sharing the same repository, allowing work on multiple branches simultaneously without switching.

**Core principle:** Systematic directory selection + safety verification = reliable isolation.

**Announce at start:** "I'm using the using-git-worktrees skill to set up an isolated workspace."

## Directory Selection Process

Follow this priority order:

### 1. Check Existing Directories

```bash
# Check in priority order
ls -d .worktrees 2>/dev/null     # Preferred (hidden)
ls -d worktrees 2>/dev/null      # Alternative
```

**If found:** Use that directory. If both exist, `.worktrees` wins.

### 2. Check CLAUDE.md

```bash
grep -i "worktree.*director" CLAUDE.md 2>/dev/null
```

**If preference specified:** Use it without asking.

### 3. Ask User

If no directory exists and no CLAUDE.md preference:

```
No worktree directory found. Where should I create worktrees?

1. .worktrees/ (project-local, hidden)
2. ~/.config/superpowers/worktrees/<project-name>/ (global location)

Which would you prefer?
```

## Safety Verification

### For Project-Local Directories (.worktrees or worktrees)

**MUST verify directory is ignored before creating worktree:**

```bash
# Check if directory is ignored (respects local, global, and system gitignore)
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

**If NOT ignored:**

Per Jesse's rule "Fix broken things immediately":
1. Add appropriate line to .gitignore
2. Commit the change
3. Proceed with worktree creation

**Why critical:** Prevents accidentally committing worktree contents to repository.

### For Global Directory (~/.config/superpowers/worktrees)

No .gitignore verification needed - outside project entirely.

## Creation Steps

### 1. Detect Project Name

```bash
project=$(basename "$(git rev-parse --show-toplevel)")
```

### 2. Create Worktree

```bash
# Claim the branch FIRST — the path below embeds the claimed name.
# (`-b` was the unguarded second creation path; it is deliberately gone.)
#
# Skip-claim guard: skip the claim iff $BRANCH_NAME is already set AND
#   git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"
# succeeds (caller passed an already-claimed name). If $BRANCH_NAME is
# set but that check fails (stale/deleted ref), STOP and surface the
# mismatch — caller-contract violation; do not claim or re-derive.
# Remote-only refs (refs/remotes/...) never satisfy the guard: the claim
# must produce a local ref, so `git worktree add` below never
# DWIM-creates one.
#
# To claim: use the environment's branch-naming convention or claim tool
# if one exists — pass $BRANCH_SHORTNAME as the requested shortname when
# set, and pass the base as its start-point argument for stacked work.
# Without one: git branch <name> [<start-point>] (never -f, never a
# checkout). Either way, capture the resulting name, e.g.:
#   BRANCH_NAME=$(claim-tool "$BRANCH_SHORTNAME")  # claim-tool = whatever the environment provides
#   (or: git branch <name> [<start-point>]; BRANCH_NAME=<name>)
# Nothing below runs until $BRANCH_NAME names an existing local ref.

# Determine full path (runs AFTER the claim; embeds the claimed name)
case $LOCATION in
  .worktrees|worktrees)
    path="$LOCATION/$BRANCH_NAME"
    ;;
  ~/.config/superpowers/worktrees/*)
    path="~/.config/superpowers/worktrees/$project/$BRANCH_NAME"
    ;;
esac

# Attach to the existing branch — no -b; this must fail rather than
# invent a ref
git worktree add "$path" "$BRANCH_NAME"
cd "$path"
```

### 3. Run Project Setup

Auto-detect and run appropriate setup:

```bash
# Node.js
if [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

### 4. Verify Clean Baseline

Run tests to ensure worktree starts clean:

```bash
# Examples - use project-appropriate command
npm test
cargo test
pytest
go test ./...
```

**If tests fail:** Report failures, ask whether to proceed or investigate.

**If tests pass:** Report ready.

### 5. Report Location

```
Worktree ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| `.worktrees/` exists | Use it (verify ignored) |
| `worktrees/` exists | Use it (verify ignored) |
| Both exist | Use `.worktrees/` |
| Neither exists | Check CLAUDE.md → Ask user |
| Directory not ignored | Add to .gitignore + commit |
| Tests fail during baseline | Report failures + ask |
| No package.json/Cargo.toml | Skip dependency install |

## Common Mistakes

### Skipping ignore verification

- **Problem:** Worktree contents get tracked, pollute git status
- **Fix:** Always use `git check-ignore` before creating project-local worktree

### Assuming directory location

- **Problem:** Creates inconsistency, violates project conventions
- **Fix:** Follow priority: existing > CLAUDE.md > ask

### Proceeding with failing tests

- **Problem:** Can't distinguish new bugs from pre-existing issues
- **Fix:** Report failures, get explicit permission to proceed

### Hardcoding setup commands

- **Problem:** Breaks on projects using different tools
- **Fix:** Auto-detect from project files (package.json, etc.)

## Example Workflow

```
You: I'm using the using-git-worktrees skill to set up an isolated workspace.

[Check .worktrees/ - exists]
[Verify ignored - git check-ignore confirms .worktrees/ is ignored]
[Claim branch: environment convention, shortname "auth" → prints BRANCH_NAME]
[Create worktree: git worktree add .worktrees/$BRANCH_NAME "$BRANCH_NAME"]
[Run npm install]
[Run npm test - 47 passing]

Worktree ready at /Users/jesse/myproject/.worktrees/$BRANCH_NAME
Tests passing (47 tests, 0 failures)
Ready to implement auth feature
```

## Red Flags

**Never:**
- Create worktree without verifying it's ignored (project-local)
- Skip baseline test verification
- Proceed with failing tests without asking
- Assume directory location when ambiguous
- Skip CLAUDE.md check

**Always:**
- Follow directory priority: existing > CLAUDE.md > ask
- Verify directory is ignored for project-local
- Auto-detect and run project setup
- Verify clean test baseline

## Integration

**Called by:**
- **brainstorming** (Phase 4) - REQUIRED when design is approved and implementation follows
- **subagent-driven-development** - REQUIRED before executing any tasks
- **executing-plans** - REQUIRED before executing any tasks
- Any skill needing isolated workspace

**Caller contract:** Callers (brainstorming, executing-plans,
subagent-driven-development) never compose branch names. Both
`$BRANCH_NAME` and `$BRANCH_SHORTNAME` are optional caller-set input
variables; when neither is set, the claim sub-step derives a name from
context. Pass either an already-claimed branch name in `$BRANCH_NAME`
(set ONLY in that case — the skip-claim guard in the `### 2. Create
Worktree` step then applies), or a shortname/task description in
`$BRANCH_SHORTNAME` with `$BRANCH_NAME` left unset; the claim sub-step
captures the created name into `$BRANCH_NAME`. Keeping the two disjoint
prevents a shortname that coincidentally matches a stale local ref from
silently skipping the claim.

**Pairs with:**
- **finishing-a-development-branch** - REQUIRED for cleanup after work complete
