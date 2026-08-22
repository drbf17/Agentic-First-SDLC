---
name: verify-gate
description: Runs the verification gates over a merge candidate — Security (SAST/dependencies/secrets), Architecture Watchdog (complexity, module size, SOLID, circular deps), and QA (coverage, mutation, CRAP, flakiness) — as three independently-vetoable verdicts. Use when build work is complete and code is ready for review, when asked to "run the gates", "verify this", "review before merge", or when a VerificationLog exists but verdict artifacts do not.
---

# Verification Gates — Stages 4, 5, 6

Three passes, three **independently-vetoable** verdicts, one shared context. Dispatch the `verifier` agent to execute them; this skill defines what it must produce and how to route the results.

**Never merge or average the three verdicts into a composite score.** A composite lets a Critical security finding be averaged away by good coverage. Each pass vetoes independently; all three must be green.

## Precondition

Stage 3 must have produced a green `VerificationLog` — every `enforcement: blocking` check in `agentic.config.yaml` exiting 0. If it hasn't, the code isn't ready for gates; return it to the build agents.

The gates **re-run** the tier-1 checks from `agentic.config.yaml` against the merge candidate. This is deliberate duplication: an agent's local green is evidence, not proof. Running checks in the loop makes failure cheap; running them again here makes it certain.

## Pass 1 — Security (runs FIRST, and alone)

Security runs before the Watchdog and is never combined with it. Rationale: Security is **pass/fail and non-negotiable**; the Watchdog is a **tunable quality score**. Different in kind, not degree.

| Finding | Action | Override |
|---|---|---|
| Critical / High SAST | hard-stop, **revert-first** | **none** |
| Hardcoded secret | hard-stop, **revert-first** | **none** |
| KEV-listed CVE | hard-stop, **revert-first** | **none** |
| Medium / Low | WARN with tracked expiry | forward-fix allowed |

Also verify: no new dependency without licence + CVE clearance; OWASP Top 10 satisfied when the spec is PII/user-input classified; no secrets in diff or agent transcript.

**A sealed spec can never pre-authorize a vulnerability class.** If the spec mandated the flagged pattern, the *spec was wrong* — route to `spec-judge` for an amendment. Never override.

## Pass 2 — Architecture Watchdog (judge-only, cannot modify code)

| Metric | Soft (warn) | Hard-fail |
|---|---|---|
| Cyclomatic complexity per function | 10 | > 15 |
| File LOC — logic (all layers) | 400 | > 600 |
| File LOC — stripped-markup JSX bulk | 550 | > 800 |
| Circular dependencies | — | any (zero tolerance) |
| Fan-out per module | 7 | — |
| Fan-in | flagged > 20 | — |
| Parameters per function | 4 | — |
| Nesting depth | 4 | — |

**Evidence rules:**
- Circular dependencies: **static-tool output only, never LLM judgment.** The model may only explain *why* a cycle exists and draft fix guidance.
- SOLID violations **are** LLM-judged, but every finding must cite a **quoted code span + the named principle**. Unevidenced "this looks bad" verdicts are invalid.
- **Never** treat a build agent's own self-assessment as authoritative.

**Anti-gaming — LOC caps reward shallow splits.** A cap satisfied by splitting one coherent module into several shallow ones makes the codebase *worse* for agent navigation. When a fix to a LOC hard-fail is a file split, check that fan-out/fan-in did not increase; if it did, flag it as a shallow-split pattern needing human review rather than passing it silently.

**Retry:** attempts 1 and 2 auto-retry with structured feedback to the owning build agent. **Attempt 3 escalates to a human** — no further auto-retries.

**Sanctioned debt:** a violation whose hash matches a `sanctioned_debt` entry in the sealed spec becomes logged WARN debt. Unmatched ⇒ hard-fail. `debtWaiver` is grantable **only by a human**.

## Pass 3 — QA

**Coverage floors** (uniform, independent of mutation tier):

| Metric | Floor |
|---|---|
| Line/branch — business logic | ≥ 90% |
| Coverage — UI (all UI, flat) | ≥ 80% |
| Branch coverage | ≥ 85% |
| ACs mapped to ≥1 test | **100%** |

**Mutation floors by risk tier** (selected via the `mutationScope` tag):

| Tier | Floor |
|---|---|
| Business logic, changed code | ≥ 75% |
| Data layer — migrations, raw queries, persistence | ≥ 85% |
| Security paths — auth, authz, input validation, crypto | ≥ 90% |
| UI with branching / state / derived logic | ≥ 75% |
| UI markup-only render bodies | exempt (coverage still applies) |

**CRAP score** — complexity × coverage, computed from data both other passes already collect. It catches what neither axis catches alone: complex code that is technically covered but not meaningfully tested. Suggested floor: CRAP ≤ 30 for business logic, tighter for data/security tiers.

**Flakiness, zero tolerance:** 5/5 deterministic on introduction; any intermittent failure across a rolling 20-run window ⇒ auto-quarantine + human escalation; **0 flaky tests permitted at merge**.

**Anti-tautology:** tests are written against the sealed spec's acceptance criteria, never against the implementation's actual behavior. A test that merely asserts what the code currently does is not a test. If the implementation diverges from the contract, that is a **contract violation to flag**, not a test to "fix".

**Orthogonality:** mutation-kill and code shape are independent. 100% mutation-killed code can still fail the Watchdog — killing mutants proves the tests exist, not that the code should exist in that shape.

## Routing failures

| Failing pass | Routes to |
|---|---|
| Security — Critical/High/KEV | revert first, then owning build agent |
| Security — Medium/Low | forward-fix on the WARN-expiry backlog |
| Watchdog | owning build agent with structured feedback (attempt 3 ⇒ human) |
| QA — coverage/mutation/CRAP | `qa-engineer` agent |
| Contract divergence from the sealed spec | `spec-judge` skill — re-seal, not a test fix |
| Spec ambiguity surfaced during review | `spec-judge` skill — re-grill |

## Output

Three artifacts in `/agent-handoffs/verdicts/`: `<spec_id>.security.json`, `<spec_id>.watchdog.json`, `<spec_id>.qa.json`. Schemas: [reference/thresholds.md](../../reference/thresholds.md)

All three green ⇒ hand to `ship-release`. Any red ⇒ route per the table above; do not proceed.
