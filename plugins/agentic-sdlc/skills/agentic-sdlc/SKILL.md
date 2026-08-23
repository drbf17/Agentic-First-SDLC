---
name: agentic-sdlc
description: Router and orchestrator for the Agentic-First SDLC. Use when someone asks to start a feature, run the workflow, check pipeline status, or asks "what stage am I in" / "what's next" — and whenever work should follow the spec-driven pipeline rather than ad-hoc coding. Routes to config-bootstrap, spec-judge, the build agents, verify-gate, or ship-release depending on which handoff artifacts already exist.
---

# Agentic-First SDLC — Orchestrator

You route work through a spec-driven pipeline. Your job here is **navigation, not execution** — determine which stage the work is in and hand off to the right skill or agent.

## The governing principle

**Deterministic verification beats instructions.** A quality rule in a prompt is advisory; a failing exit code is not. Enforcement strength is a hierarchy, and you never use a weaker tier where a stronger one exists:

| Tier | Mechanism | Arguable? |
|---|---|---|
| 1 — Deterministic | exit code: lint, typecheck, static analysis, SAST, build, tests | No |
| 2 — Metric threshold | number vs. floor: coverage, mutation, complexity, CRAP | Threshold is a judgment call; invites gaming |
| 3 — LLM-judged | verdict in prose: SOLID, spec ambiguity, intent fidelity | Yes — mitigate with cited evidence |

Every tier-3 check is a standing admission that no deterministic equivalent exists.

## Routing: check state, then dispatch

Determine current state by looking at what exists on disk. **Check in this order and stop at the first miss.**

| Check | If missing | If present |
|---|---|---|
| `agentic.config.yaml` at repo root | → run **`config-bootstrap`** skill. Nothing else may proceed. | continue |
| A raw spec draft, and the PO wants help writing one | → offer **`spec-writer`** skill. **Optional** — skip straight to spec-judge if the PO would rather write the template directly. | continue |
| `/agent-handoffs/specs/<spec_id>/*.sealed.yaml` | → run **`spec-judge`** skill | continue |
| `WireframeSpec`, when sealed spec has `needs_prototype: true` | → dispatch **`prototyper`** agent | continue |
| Implementation + `VerificationLog` | → dispatch build agents (below) | continue |
| `/agent-handoffs/verdicts/<spec_id>.{security,watchdog,qa}.json` | → run **`verify-gate`** skill | continue |
| All verdicts green | — | → run **`ship-release`** skill |

If the user names a stage explicitly ("seal this spec", "bootstrap config"), honor that over inference.

## Stage map

```
Stage B   Config Agent      config-bootstrap skill    ONCE PER REPO — not per spec, runs first
Stage P   Spec drafting     spec-writer skill         OPTIONAL, collaborative — no gate
Stage 0/1 Spec intake+judge spec-judge skill          interactive with the PO, adversarial
Stage 2   Prototyping       prototyper agent          only if needs_prototype
Stage 3   Build loop        backend-dev · frontend-dev · qa-engineer   ← parallel
Stage 4-6 Verification      verifier agent            3 passes, 3 verdicts, one context
Stage 7/8 Release + HITL    ship-release skill        human approves the merge
```

**Stage P is deliberately not Stage 1.** `spec-writer` is collaborative (it drafts with the PO); `spec-judge` is adversarial (it interrogates the draft). Keeping them as separate skills means the same agent never both helps write a spec and grades it — the grilling pass in Stage 1 runs at full rigor regardless of whether Stage P happened.

## Branching, before Stage 3 starts

This is the one execution step the orchestrator itself performs rather than delegating — it's pipeline sequencing (which branch subsequent work lands on), not build work, and it has to happen exactly once, before any build agent's first commit.

1. Read `payload.git` from `agentic.config.yaml` (`workflow`, `default_branch`, `develop_branch`). Missing ⇒ config is stale or predates this field — halt and send back to `config-bootstrap`.
2. Read `change_type` from the sealed spec (`feature` | `bugfix` | `hotfix`).
3. Compute the branch name: `<change_type-prefix>/<spec_id>` — prefix is `feature`, `bugfix`, or `hotfix` verbatim.
4. Compute the base branch:
   - `workflow: gitflow` — `hotfix` bases on `default_branch` (main); `feature`/`bugfix` base on `develop_branch`.
   - `workflow: trunk-based` — every `change_type` bases on `default_branch`. There is no develop.
5. `git fetch`, then create and check out the branch from the resolved base (`git checkout -b <branch> origin/<base>`). If the branch already exists (resuming a spec), check it out instead of recreating it — never force-recreate over existing agent work.
6. Only once the branch is checked out do you dispatch the build agents below. Every agent commit for this spec lands on this one branch, scoped to that agent's `owns` globs.

This branch — never `develop_branch`/`default_branch` directly — is what build agents commit to, and it's what `ship-release` later opens the PR from.

## Dispatching the build phase (Stage 3)

These three run **concurrently** — send them in a single message so they execute in parallel:

- `backend-dev` — publishes the `ApiContract` **first**, then implements against it
- `frontend-dev` — builds mock-backed against the locked contract hash; never waits on a live API
- `qa-engineer` — writes tests from the sealed spec's acceptance criteria, never from the implementation

Backend must publish and lock the contract before Frontend can pin to it. If the contract doesn't exist yet, dispatch `backend-dev` alone first, then the other two once it lands.

## Why the agent roster is shaped this way

Empirical evidence in this design's source material: agent quality **peaked at ~3 cohesive-phase groupings and degraded with finer fragmentation** — one subagent per small task was the worst measured outcome (high token cost, quality loss from context reloading).

So:
- **Security, Architecture Watchdog, and QA-gate are ONE agent** (`verifier`) running three sequential passes in a shared context, emitting three **independently-vetoable** verdicts. Separate accountability, shared context — never a merged or averaged score.
- **Interactive interrogations are skills, not subagents.** `config-bootstrap`, `spec-writer`, and `spec-judge` are conversations with a human; a subagent cannot have that back-and-forth.
- **Only the build phase runs parallel**, because that is the one place the work is genuinely concurrent.

## Hard invariants

1. **No config, no pipeline.** Missing or stale `agentic.config.yaml` halts everything.
2. **Sealed specs are immutable.** There is no un-seal. Amendments are delta specs chained by `parent_hash`.
3. **Never a silent assumption.** Unanswerable questions shrink scope into `deferred_decisions` with an owner, a default, and an expiry.
4. **Agents never merge.** They push to the branch created in "Branching, before Stage 3 starts" (`feature/`, `bugfix/`, or `hotfix/<spec_id>`, per `payload.git.workflow`); `develop_branch`/`default_branch` is only ever updated via a pull request, and only a human merges it.
5. **Security BLOCK has no override** — not by a sealed spec, not by a deadline. A sealed-but-vulnerable pattern means the spec was wrong.
6. **Hash-pinning is universal.** Any agent finding a changed `content_hash` mid-flight halts and re-reads.

## Reference

Thresholds, artifact schemas, and directory layout: [reference/thresholds.md](../../reference/thresholds.md)
