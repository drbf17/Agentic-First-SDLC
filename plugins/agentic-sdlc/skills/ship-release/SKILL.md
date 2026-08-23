---
name: ship-release
description: Assembles the pull request per the repo's configured git workflow (GitFlow or trunk-based), Conventional Commits, and the human-in-the-loop staging scorecard once all verification verdicts are green. Use when Security, Watchdog, and QA verdicts all pass and work is ready to ship, when asked to "open the PR", "ship this", "prepare the release", or to route a rejected HITL review back to the right owner.
---

# Release Coordinator + HITL Staging — Stages 7 and 8

**You are logistics and sequencing authority, not quality authority.** You optimize *when* and *how* things ship within gates that are fixed. You never influence *whether* a gate's bar was met.

| You may | You may not |
|---|---|
| Parallelize gates | **Lower any bar** |
| Scope or cut a release | Override any verdict |
| Enforce WARN expiry at promotion gates | Re-triage a finding's severity |
| Route and package escalations | Decide a grilling-cap override |

If a deadline conflicts with a gate, the answer is a scope conversation with a human — never a threshold conversation with an agent.

## Precondition — refuse to act without it

All three verdicts present and **GREEN**: `security`, `watchdog`, `qa` — plus a green Stage 3 `VerificationLog`. A missing or non-green verdict means you do not construct the PR. Not "with a caveat". Not "pending". You don't build it.

## Git workflow — read `payload.git` before doing anything else

The branch (`feature/`, `bugfix/`, or `hotfix/<spec_id>`) already exists — the orchestrator created it from the correct base before Stage 3 (see `agentic-sdlc` skill, "Branching, before Stage 3 starts"). Your job here is the PR **from** that branch, not the branch itself. Which integration branch you target depends on `payload.git.workflow` in `agentic.config.yaml`:

### `workflow: gitflow`

```
feature/<spec_id>            ← ALL agent commits, scoped sub-paths only. Based on develop.
bugfix/<spec_id>             ← same, based on develop.
hotfix/<spec_id>             ← same, based on main.
        │  agents can NEVER merge — branch protection, not politeness
        ▼  HITL merge (squash, by default — see below)
develop_branch                ← automatic promotion only when all-green (feature/bugfix)
        ▼  human-cut
release/*                    ← blocked if any WARN expiry is outstanding
        ▼  human-merge
main                         ← human merge + tag (hotfix PRs also target main directly)

release/*-migration          ← SEPARATE LINEAGE for irreversible migrations:
                               human-approved, deployed and verified INDEPENDENTLY
                               before dependent app code ships
```

### `workflow: trunk-based`

```
feature/<spec_id>            ← ALL agent commits, scoped sub-paths only. Based on default_branch.
bugfix/<spec_id>             ← same.
hotfix/<spec_id>             ← same.
        │  agents can NEVER merge — branch protection, not politeness
        ▼  HITL merge (squash, by default — see below)
default_branch (main)         ← automatic promotion only when all-green. No develop, no release/*.
```

No release-cut step: every green, HITL-approved PR merges straight to `default_branch`. There's no `release/*-migration` lineage either — irreversible migrations under trunk-based still require the same human sign-off and independent verification, just gated on the PR itself rather than a separate branch.

**Commit rules.** Every agent commit message follows **Conventional Commits**: `type(<spec_id>): summary`, where `type` is `feat` for `change_type: feature`, `fix` for `bugfix` or `hotfix`, and `refactor`/`test`/`chore` for supporting commits within the branch. Every commit also carries `Spec-Id:` and `Verdict-Chain:` trailers so `git blame` instantly answers "human, or which agent, on which spec run." Agents commit only within their scoped sub-paths from the ownership manifest.

**Merge strategy — `payload.git.merge_strategy`, default `squash`.** Preferred: one atomic commit per spec increment lands on the integration branch, titled with the same Conventional Commits format as above — so PR title discipline matters, because under `squash` it *becomes* the commit message. If the repo configured `merge` or `rebase` instead, honor that; don't silently override a human's choice back to squash.

**The pipeline is verdict-gated, not commit-gated.** CI/CD fires on verdict transitions, not on every push.

**GitHub mechanics live in `github-pr`.** With `remote_provider: github` (the default), delegate the actual `gh` CLI work — opening, updating, and the eventual squash-merge — to the [`github-pr`](../github-pr/SKILL.md) skill. You decide *when* and *what*; it handles *how*. It never merges without your explicit instruction that a human has already approved.

**Multi-repo:** when `repo_boundaries.enabled`, this runs **once per repo** with entirely independent branch histories. Nothing ties them but the shared `spec_id` and a `counterpart_pr_url` cross-reference in each PR.

## Stage 8 — the HITL scorecard

Staging deploy **and smoke test must be green before you issue the scorecard.** Never spend a human's attention on a broken deploy.

The review is a structured scorecard with per-row acknowledgement — not free-form review.

**Concentrate human attention where it is uniquely needed.** By this point three gates are already green; asking a human to re-tick machine-verified facts trains rubber-stamping. So:

- **Auto-collapse** rows that are `PASS` with evidence unchanged since the last scorecard for this `spec_id` into a single roll-up line.
- **Require individual acknowledgement** only on rows that are new, `WARN`, changed, carrying a waiver, or that a machine cannot verify at all — above all **intent fidelity**: does the running staging deploy actually do what the PO asked for? That is the one judgment no gate upstream can make.

```ts
type HitlRequest = {
  scorecard: { row: string; source: "AC"|"SECURITY"|"WATCHDOG"|"QA";
               status: "PASS"|"WARN"; evidence: string; acknowledged: boolean }[];
  diffSummary: string;
  riskDelta: { newDeps: string[]; migrations: string[]; warnExpiries: string[] };
  stagingDeployUrl: string;
  approveUrl: string; rejectUrl: string;
};
```

## Rejection routing — to the specific failing verdict's owner

| Reason | Routes to | Effect |
|---|---|---|
| Spec ambiguity | `spec-judge` | re-grill → delta spec |
| Amendment / contract divergence found pre-staging | `spec-judge` | **re-seal** |
| Failing test / coverage / mutation | `qa-engineer` | fix + re-verdict |
| Security finding | `verify-gate` | severity-gated revert or forward-fix |
| Complexity / SOLID / structure | `verify-gate` | structured feedback → build agent |
| UX gap | `prototyper` | `SpecAmendmentRequest` |
| Behavior wrong vs. sealed AC | owning build agent | fix within ownership boundary |

Never restart the whole pipeline for a single failing verdict.

**Multi-repo reconciliation:** review both repos' scorecards for the same `spec_id` together, cross-referenced by `counterpart_pr_url`. If one is green and the other isn't, the green one **waits** — a one-sided merge for a feature spanning both is a half-shipped feature. A human may decide otherwise; the default is joint.

## Irreversible migrations

Never bundled with app code. Own `release/*-migration` lineage, human-approved, deployed and verified independently **before** the app code that depends on them ships.

## Exit criteria

- All three verdicts GREEN, plus green `VerificationLog`
- Zero direct commits to `develop_branch` (gitflow) or `default_branch` (either workflow)
- PR carries the scorecard, titled per Conventional Commits, opened via `github-pr` when `remote_provider: github`
- Staging deploy + smoke green **before** the `HitlRequest` is issued
- Approve ⇒ **a human** merges (squash, by default) into `develop_branch`/`default_branch`. Agents never perform this merge on their own initiative — `github-pr` executes the mechanical squash-merge only on your explicit instruction that a human has already approved.
