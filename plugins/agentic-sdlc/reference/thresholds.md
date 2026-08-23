# Reference — thresholds, artifacts, and layout

Loaded on demand. The full rationale for every number here lives in the workflow architecture document; this file is the operational lookup.

## Repository layout

```
<repo-root>/
├── agentic.config.yaml               ← Stage B. Repo-scoped, NOT under /agent-handoffs
└── agent-handoffs/
    ├── specs/<spec_id>/
    │   ├── <spec_id>.v0.raw.md        ← Stage 0 (PO submission)
    │   ├── <spec_id>.v1.sealed.yaml   ← Stage 1
    │   └── deltas/<parent_hash>-<n>.yaml
    ├── wireframes/<spec_id>.wireframe.json    ← Stage 2
    ├── contracts/<spec_id>.api.v<semver>.yaml ← Stage 3 (Backend, published FIRST)
    ├── manifests/
    │   ├── <spec_id>.ownership.yaml           ← committed BEFORE build starts
    │   └── <spec_id>.frontend.manifest.json
    ├── verdicts/
    │   ├── <spec_id>.verification.json        ← Stage 3 tier-1 check runs
    │   ├── <spec_id>.security.json            ← Stage 4
    │   ├── <spec_id>.watchdog.json            ← Stage 5
    │   └── <spec_id>.qa.json                  ← Stage 6
    └── release/<spec_id>.hitl-request.json    ← Stage 8
```

## Standard artifact envelope

Every handoff artifact carries these fields so any agent or human can validate provenance without asking anyone:

```yaml
schema_version: "1.0"
artifact_type: SealedSpec | WireframeSpec | ApiContract | OwnershipManifest
             | ComponentManifest | VerificationLog | SecurityVerdict
             | ReviewVerdict | QaVerdict | HitlRequest
spec_id: string
content_hash: string      # sha256 of payload — what downstream agents pin to
parent_hash: string?      # upstream artifact this derives from
produced_by:
  agent: string
  repo: string
  run_id: string
  model_version: string   # which model rendered the judgment
produced_at: string       # ISO 8601
payload: { ... }
```

**Resumability rule.** Before acting, verify `content_hash` matches what you expect to pin to, and that every `parent_hash` resolves back to the `SealedSpec`. A broken chain halts the agent with a structural error.

## Consolidated numeric gates

| Stage | Metric | Threshold |
|---|---|---|
| **B — Config** | mandatory categories configured or waived | **4 of 4** (lint · typecheck · static · sast) |
| B | commands written without a verified successful run | 0 |
| B | waivers missing `granted_by` or `expires_at` | 0 |
| **1 — Spec** | avg ambiguity | **< 0.15** |
| 1 | max single-item ambiguity | **≤ 0.4** |
| 1 | grilling iterations | ≤ 5 → human Tech Lead |
| **2 — Prototype** | AC traceability | 100% |
| 2 | gate criteria | 6 (incl. blocking PII scan) |
| **3 — Build** | blocking tier-1 checks failing at commit | **0** |
| 3 | self-repair attempts per root cause | ≤ 3 |
| 3 | component size / prop-drilling (FE) | ~150 LOC, 1 responsibility / ≤3 levels |
| 3 | N+1 queries (BE) | 0 |
| **4 — Security** | Critical / High / secrets / KEV | **0 — hard-stop, no override** |
| **5 — Watchdog** | cyclomatic complexity per function | 10 soft / **>15 hard-fail** |
| 5 | logic LOC per file | 400 soft / **>600 hard-fail** |
| 5 | stripped-markup JSX bulk per file | 550 soft / **>800 hard-fail** |
| 5 | circular dependencies | **0** |
| 5 | fan-out / fan-in / params / nesting | 7 / >20 flagged / 4 / 4 |
| 5 | retries before human escalation | 2, escalate on attempt **3** |
| **6 — QA** | coverage: business logic / UI / branch | ≥90% / ≥80% / ≥85% |
| 6 | AC-to-test mapping | **100%** |
| 6 | mutation: business / data / security paths | ≥75% / ≥85% / ≥90% |
| 6 | CRAP score (business logic) | ≤ 30 |
| 6 | flakiness | 5/5 deterministic, 20-run window, **0 flaky at merge** |
| **7 — Release** | green upstream verdicts required | **3** + green VerificationLog |

## Key type shapes

```ts
type SealedSpec = {
  content_hash: string; spec_id: string; parent_hash?: string;
  change_type: "feature" | "bugfix" | "hotfix";   // selects branch prefix + base branch, Stage 3
  acceptance_criteria: AC[];
  edge_cases: EdgeCase[];              // >= number of decision points
  nfrs: QuantifiedNFR[];               // every one carries a number and a unit
  complexity_budget_hint: { max_cyclomatic?: number; max_file_loc?: number };  // ADVISORY
  deferred_decisions: { item: string; owner: string; default: string;
                        expires_at: string; sanctioned_debt?: SanctionedDebt[] }[];
  needs_prototype: boolean;
  ambiguity_score: { avg: number; max_item: number };
  iterations_used: number;             // <= 5
  owasp_required: boolean;
  repo_boundaries?: RepoBoundaries;    // passed through untouched by grilling
};

type VerificationLog = {
  spec_id: string; config_hash: string;
  runs: { check_id: string; category: string; stage: "dev-loop"|"pre-push"|"gate";
          exit_code: number; passed: boolean;
          enforcement: "blocking"|"report-only";
          duration_seconds: number; attempt: number; at: string }[];
  waivers_active: string[];
};

type SecurityVerdict = {
  status: "PASS" | "BLOCK" | "WARN";
  findings: { severity: "CRITICAL"|"HIGH"|"MEDIUM"|"LOW"; rule: string;
              file: string; line: number; expiresAt?: string }[];
  dependencyDecisions: { pkg: string; decision: "APPROVED"|"REJECTED"; reason: string }[];
};

type ReviewVerdict = {
  status: "PASS" | "FAIL" | "ESCALATE"; attemptNumber: 1|2|3;
  violatedRules: { rule: string; file: string; measured: number; threshold: number;
                   evidence?: { span: string; principle: string } }[];
  requiredFixes: string[];
};
```

## The enforcement hierarchy

| Tier | Mechanism | Examples | Arguable? |
|---|---|---|---|
| 1 — Deterministic | process exit code | lint, tsc, static analysis, SAST, build, tests | No |
| 2 — Metric threshold | number vs. floor | coverage, mutation, complexity, CRAP, LOC | Threshold is a judgment call; invites gaming |
| 3 — LLM-judged | verdict in prose | SOLID, spec ambiguity, intent fidelity | Yes |

**Never use a weaker tier where a stronger one is available.** Every tier-3 check is a standing admission that no deterministic equivalent exists for that property.
