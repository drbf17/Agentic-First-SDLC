# Agentic-First SDLC

A spec-driven development lifecycle for Claude Code: seven skills and five subagents that take a feature from a Product Owner's written spec through implementation, verification, and a human-approved merge — with deterministic quality gates enforced inside the development loop rather than requested in a prompt.

Distributed as a Claude Code plugin. Install once per repo; teammates get it automatically.

---

## Table of contents

- [The idea in one page](#the-idea-in-one-page)
- [Architecture](#architecture)
- [Installation](#installation)
- [Usage](#usage)
- [Repository layout](#repository-layout)
- [Customizing](#customizing)
- [What this does not do](#what-this-does-not-do)

---

## The idea in one page

AI made code cheap to produce and expensive to trust. The bottleneck moved from typing to verifying. This workflow is built on one consequence of that shift:

> **Do not put a quality requirement in an agent's prompt when you could put it in tooling the agent cannot talk its way past.**

An instruction in context is advisory. A failing exit code is not. An agent under context pressure will rationalize — it will explain why this case is the exception, and it will sound reasonable doing it. A deterministic check has no context to be pressured by.

That produces a hierarchy, and the rule is **never use a weaker tier where a stronger one is available**:

| Tier | Mechanism | Examples | Can the agent argue with it? |
|---|---|---|---|
| **1 — Deterministic** | process exit code | linter, `tsc`, static analysis, SAST, build, tests | **No** |
| **2 — Metric threshold** | number vs. floor | coverage, mutation score, complexity, CRAP | Not directly — but the threshold is a judgment call, and thresholds invite gaming |
| **3 — LLM-judged** | verdict in prose | SOLID violations, spec ambiguity, intent fidelity | **Yes** — mitigated by requiring cited evidence |

Every tier-3 check in this system is a standing admission that no deterministic equivalent exists for that property.

Tier 1 is the strongest instrument available, and it is the only tier a workflow document **cannot** specify for you: `cyclomatic ≤ 10` is stack-agnostic, `pnpm tsc --noEmit` is not. That is why the first thing this system does in a new repository is interrogate a human about the toolchain and write the answers down as executable config.

---

## Architecture

### Twelve components, three groups

```
                        ┌─ Stage B ──────────────────────────────────┐
                        │  config-bootstrap  (skill, interactive)  │  ONCE PER REPO
                        │  → writes agentic.config.yaml            │  runs first
                        └──────────────────┬───────────────────────┘
                        ┌─ Stage P (optional) ─────────────▼─────────┐
                        │  spec-writer  (skill, interactive)         │  collaborative,
                        │  → drafts a raw spec with the PO           │  no gate, skippable
                        └──────────────────┬──────────────────────┘
                                           │ binds everything below
   ┌───────────────────────────────────────▼──────────────────────────────────┐
   │  Stage 0/1   spec-judge      (skill, interactive)  → SealedSpec           │
   │              adversarial — full rigor; also recommends architecture      │
   │              review via architecture_recommendation, never gates on it   │
   │                                                                           │
   │              orchestrator branches HERE — immediately after the seal,    │
   │              before Stage 2 — and commits the sealed spec to it          │
   │                                                                           │
   │  Stage 1.5   architecture-judge (skill, interactive) → ArchitectureDecisionRecord│
   │              OPTIONAL, human-invoked only — never auto-dispatched        │
   │                                                                           │
   │  Stage 2     prototyper      (agent)               → WireframeSpec        │
   │                                                                           │
   │  Stage 3     backend-dev ─┐                                               │
   │              frontend-dev ─┼─ (agents, PARALLEL)   → code + contract      │
   │              qa-engineer  ─┘                       + VerificationLog      │
   │                                                                           │
   │  Stage 4-6   verify-gate     (skill) → dispatches verifier (agent)        │
   │              3 passes, 3 independently-vetoable verdicts, ONE context     │
   │                                                                           │
   │  Stage 7/8   ship-release    (skill) → PR + HITL scorecard → HUMAN MERGES │
   └───────────────────────────────────────────────────────────────────────────┘
```

### Why skills for some things and subagents for others

This split is deliberate and worth understanding before you modify it.

**Skills** run in the main conversation. They can talk to you, ask follow-up questions, and wait for your answer.

**Subagents** run in their own context window and return a report. They are good at context-heavy, parallelizable work — and they cannot hold a back-and-forth with you.

So:

| Component | Type | Why |
|---|---|---|
| `spec-writer` | **skill**, optional | Collaborative drafting with a human. Deliberately a *different* skill from `spec-judge` — the agent that helps write a spec shouldn't also be the one grading it. |
| `config-bootstrap` | **skill** | It is an interrogation of a human. A subagent can't conduct one. |
| `spec-judge` | **skill** | Same — it grills the PO across up to 5 iterations of dialogue, adversarially. Also flags whether the spec needs a special architecture, but never decides that itself. |
| `architecture-judge` | **skill**, optional | `spec-judge`'s structural twin for design instead of requirements — grills an architect or tech lead's proposal the same adversarial way. **Human-invoked only**; the orchestrator never dispatches it. |
| `verify-gate`, `ship-release` | **skills** | Procedures the main agent follows, with human decision points. |
| `backend-dev`, `frontend-dev`, `qa-engineer` | **agents** | Genuinely concurrent work on separate file boundaries. |
| `prototyper`, `verifier` | **agents** | Context-heavy analysis producing a structured report. |

### Why the verifier is one agent and not three

The source research behind this design measured agent granularity directly: quality **peaked at ~3 cohesive-phase groupings and degraded with finer fragmentation.** One subagent per small task was the *worst* measured outcome — high token cost and quality loss from constant context reloading.

So Security, Architecture Watchdog, and QA are **one agent running three sequential passes in a shared context**, emitting **three independently-vetoable verdicts**.

That last part matters: the verdicts are never merged or averaged. A composite score lets a Critical security finding be averaged away by good coverage. Separate accountability, shared context.

### The verifier has no Write tool

`verifier.md` grants `Read, Glob, Grep, Bash` — deliberately no `Write`, no `Edit`. A reviewer that can silently patch its own findings is not a reviewer.

This is the Determinism Principle applied to tool grants: **remove the capability rather than instructing against it.** "Don't modify code" in a prompt is a tier-3 request; withholding the tool is tier 1.

### The stage gates

| Stage | Gate | Threshold |
|---|---|---|
| P *(optional)* | none — `spec-writer` never scores or blocks | n/a |
| B | mandatory check categories configured or waived | **4 of 4** (lint · typecheck · static · SAST) |
| 1 | spec ambiguity | avg **< 0.15** AND max item **≤ 0.4**, ≤ 5 iterations |
| 1.5 *(optional, human-invoked)* | architecture ambiguity, same math as Stage 1 | avg **< 0.15** AND max item **≤ 0.4**, ≤ 5 iterations — never blocks Stage 2/3 |
| 2 | acceptance criteria traced to screens | 100%, 6 gates incl. blocking PII scan |
| 3 | blocking tier-1 checks failing at commit | **0** |
| 4 | Critical / High SAST, secrets, KEV CVEs | **0 — no override, ever** |
| 5 | cyclomatic complexity / logic LOC per file | 10 soft, **>15 fail** / 400 soft, **>600 fail** |
| 6 | coverage (logic/UI/branch) · mutation (logic/data/security) | 90/80/85% · 75/85/90% |
| 7 | green verdicts required before a PR is built | **3** + green VerificationLog |

Full table and artifact schemas: [`plugins/agentic-sdlc/reference/thresholds.md`](plugins/agentic-sdlc/reference/thresholds.md)

---

## Installation

### Prerequisites

- Claude Code
- A git repository
- The four verification tools your stack needs (linter, type checker, static analysis, SAST) — the Config Agent will find and verify whatever you already have

### One-time: publish this repo

Push this repository to GitHub, then replace the placeholder in **two** files with your org/user:

```bash
# .claude-plugin/marketplace.json  and  templates/settings.json
sed -i '' 's|REPLACE-ME|your-org|g' .claude-plugin/marketplace.json templates/settings.json
git add -A && git commit -m "Point marketplace at your-org" && git push
```

### Option A — plugin marketplace (recommended)

In any repo where you want the workflow:

```
/plugin marketplace add your-org/agentic-first-sdlc
/plugin install agentic-sdlc@agentic-first-sdlc
```

Verify: `/plugin list` shows `agentic-sdlc`, and typing `/` lists the seven skills.

### Option B — auto-bootstrap your whole team (recommended for shared repos)

Commit the marketplace config so teammates need to run **nothing**:

```bash
mkdir -p .claude
cp templates/settings.json .claude/settings.json   # edit REPLACE-ME first
git add .claude/settings.json && git commit -m "Add Agentic-First SDLC" && git push
```

```json
{
  "extraKnownMarketplaces": {
    "agentic-first-sdlc": {
      "source": { "source": "github", "repo": "your-org/agentic-first-sdlc" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": ["agentic-sdlc@agentic-first-sdlc"]
}
```

On next launch, teammates are prompted once to trust the marketplace; after that the plugin installs and stays updated automatically.

### Option C — manual install (no plugin system)

For forking and modifying the skills, or where plugins aren't available:

```bash
git clone https://github.com/your-org/agentic-first-sdlc.git
cd /path/to/your/project
/path/to/agentic-first-sdlc/install.sh          # → ./.claude
/path/to/agentic-first-sdlc/install.sh --user   # → ~/.claude, all projects
```

The script refuses to overwrite existing files without confirming, and supports `--force`, `--target DIR`, and `--uninstall`.

**Trade-off:** manual installs do not auto-update. Re-run with `--force` from a fresh checkout to pull changes.

### Recommended: add the project instructions

```bash
cp templates/CLAUDE.md ./CLAUDE.md   # then add your domain context
```

### Updating

| Method | How |
|---|---|
| Plugin, autoUpdate on | Automatic |
| Plugin, manual | `/plugin marketplace update agentic-first-sdlc` |
| Manual install | `git pull && ./install.sh --force` |

---

## Usage

### First run in a new repository

```
You:  /config-bootstrap
```

The Config Agent reads your repo, then asks one category at a time:

> I found `eslint.config.js` and a `lint` script. I propose `pnpm eslint . --max-warnings=0`. Confirm, correct, or replace?

It **runs each command before writing it** — a command that errors on invocation is rejected on the spot. It will not write a check it hasn't seen execute, because an unverified command fails open the first time it matters and looks configured until then.

Output: `agentic.config.yaml` at your repo root. Nothing else in the pipeline runs until it exists.

### A feature, start to finish

**1. Write the spec.** Copy [`reference/spec-template.md`](plugins/agentic-sdlc/reference/spec-template.md), fill it in, save to `agent-handoffs/specs/<spec_id>/<spec_id>.v0.raw.md`.

> **Don't know where to start? This step is optional.**
> ```
> You:  /spec-writer  I want to add guest checkout to the cart flow
> ```
> `spec-writer` talks through the feature with you in plain language and fills in the template on your behalf — including a starting-point number for NFRs you're unsure of (marked `# DRAFT` so the next step knows exactly where to press). It never scores or blocks anything; if you'd rather fill in the template yourself, skip straight to step 2.

**2. Get grilled.**

```
You:  /spec-judge  agent-handoffs/specs/checkout-guest/checkout-guest.v0.raw.md
```

```
## Iteration 1 of 5

### Checklist findings
- happy_path[3] "user confirms order" has no matching acceptance criterion
- actors[1] "Guest shopper" has no authz behavior defined
- nfrs[0] value "fast" is unquantified

### Questions
1. When the payment provider times out after 30s, does the order persist as
   pending, or roll back entirely?
2. Guest shopper — can they view an order after session expiry? Yes/no.
3. What p95 latency, in ms, is acceptable for order confirmation?

### Ambiguity scoring
| Item | Score | Why |
| payment timeout behavior | 0.7 | Undefined; changes the data model |
| guest post-session access | 0.4 | Two readings, both plausible |
| confirmation latency | 0.3 | Sensible default exists but unstated |
**avg = 0.47 | max_item = 0.70 | seal requires avg < 0.15 AND max_item <= 0.4**

### Verdict
CONTINUE (iteration 2)
```

Answer, iterate. It seals when the math clears. Can't answer something? Say so — scope shrinks and the item is logged with an owner, a default, and an expiry. That's a supported outcome; a silent guess is not.

The moment it seals, two things happen automatically:

- The orchestrator creates and checks out this spec's working branch (`feature/checkout-guest`, off the base your `payload.git.workflow` specifies) and commits the sealed spec to it as the first commit — before Stage 2 even starts, so every handoff artifact from here on is versioned, not just files on disk.
- `spec-judge` states an `architecture_recommendation`: `current_architecture_sufficient`, or `requires_review` with the specific driver named (new datastore, new integration, an NFR the current design can't hit, etc).

> **Design needs a second look? This step is optional.**
> ```
> You:  /architecture-judge  agent-handoffs/architecture/checkout-guest.v0.raw.md
> ```
> `architecture-judge` grills whoever wrote the proposal — the same adversarial stance and ambiguity math as `spec-judge`, aimed at the design instead of the requirements — and seals an `ArchitectureDecisionRecord` that Backend and Frontend then pin to alongside the spec. **Nothing downstream blocks on this.** If you skip it, Stage 3 proceeds against the sealed spec alone, same as always — that's a supported choice, not a gap.

**3. Build.** Backend publishes and locks the API contract first; Frontend builds mock-backed against that hash without waiting for a live API; QA writes tests from the acceptance criteria — never from the implementation.

```
You:  Run the build phase for checkout-guest
```

Each agent runs your `dev-loop` checks on every write-verify cycle and cannot commit while a blocking check fails.

**4. Verify.**

```
You:  /verify-gate
```

```
security: PASS
watchdog: FAIL
  src/checkout/orderStateMachine.ts:142 — cyclomatic 18, hard-fail >15
    SRP: `processOrder` handles validation, payment, inventory, and email
    > if (order.status === 'pending' && payment.ok && ...
    Required: extract payment and notification concerns
qa:       FAIL
  Mutation 71% on src/checkout/ (floor 75%) — 4 survivors in refund logic
  AC "guest can retry failed payment" has no mapped test
```

**5. Ship.**

```
You:  /ship-release
```

Opens the PR with the scorecard attached, deploys to staging, runs smoke tests, and hands you a review focused on what a machine can't check — above all: *does the running deploy actually do what the PO asked for?* PASS rows with unchanged evidence collapse into a roll-up so your attention goes where it's needed.

**A human merges. Agents never do.**

### Common commands

| Intent | Say |
|---|---|
| "What stage am I in?" | `/agentic-sdlc` |
| Set up a new repo | `/config-bootstrap` |
| Help drafting a spec (optional) | `/spec-writer` |
| Seal a spec | `/spec-judge <path>` |
| Stress-test an architecture decision (optional) | `/architecture-judge <path>` |
| Run the gates | `/verify-gate` |
| Open the PR | `/ship-release` |
| Wireframes for a spec | "Run the prototyper for `<spec_id>`" |

---

## Repository layout

```
agentic-first-sdlc/
├── .claude-plugin/marketplace.json      ← marketplace manifest (edit REPLACE-ME)
├── plugins/agentic-sdlc/
│   ├── .claude-plugin/plugin.json
│   ├── skills/                          ← 7 skills, auto-discovered
│   │   ├── agentic-sdlc/SKILL.md        ← router
│   │   ├── spec-writer/SKILL.md         ← Stage P, optional, collaborative
│   │   ├── config-bootstrap/SKILL.md    ← Stage B
│   │   ├── spec-judge/SKILL.md          ← Stages 0-1, adversarial
│   │   ├── architecture-judge/SKILL.md  ← Stage 1.5, optional, human-invoked only
│   │   ├── verify-gate/SKILL.md         ← Stages 4-6
│   │   └── ship-release/SKILL.md        ← Stages 7-8
│   ├── agents/                          ← 5 subagents
│   │   ├── prototyper.md · backend-dev.md · frontend-dev.md
│   │   ├── qa-engineer.md · verifier.md (judge-only, no Write tool)
│   │   └──
│   └── reference/                       ← loaded on demand, not per-turn
│       ├── thresholds.md · config-schema.md · spec-template.md · architecture-template.md
├── templates/
│   ├── settings.json                    ← team auto-bootstrap
│   └── CLAUDE.md                        ← project instructions
├── install.sh                           ← manual install path
└── agentic-first-sdlc-workflow.md       ← full design rationale
```

In a **consuming** repo, the workflow produces:

```
your-project/
├── agentic.config.yaml          ← Stage B. Repo root, deliberately not hidden.
├── CLAUDE.md
├── .claude/settings.json
└── agent-handoffs/              ← every stage's output, plain files, git-tracked
    ├── specs/ · architecture/ (optional) · wireframes/ · contracts/ · manifests/ · verdicts/ · release/
```

`/agent-handoffs` is a plain visible directory, not a database or a service. Git already provides tamper-evident history, works offline, and needs no infrastructure to run. Any agent — or human — can pick up a spec cold by reading these files.

---

## Customizing

**Thresholds** live in `reference/thresholds.md` and the skill bodies. If your team disagrees with a number, change it — but change it deliberately and write down why.

**Phasing in gates.** Every check supports `enforcement: report-only`, which runs and logs but blocks nothing. Introduce a new check as `report-only`, gather real pass/fail data for a few specs, then flip it to `blocking` once you know the noise floor. This is the safest rollout path for a team new to gated workflows.

**Models.** Build agents default to `sonnet`, the verifier to `opus` (judgment-heavy). Change the `model:` frontmatter to taste; `inherit` uses your session model.

**Faster inner loop.** Consider `permissionMode: acceptEdits` on the build agents so they don't prompt on every file write. Decide this deliberately — it grants unattended edit rights within their ownership boundary.

**Adding a stage.** Prefer extending an existing skill over adding a component. The granularity research is unambiguous: more agents made quality *worse*, not better.

---

## What this does not do

Stated plainly, because knowing the boundaries matters more than a feature list.

**claude.ai Projects cannot run this.** Verified against current documentation: claude.ai has no per-project skills (they're account-wide, uploaded manually as `.zip`), no subagents, no `CLAUDE.md`, and no GitHub sync for project knowledge. There is no configuration that makes a git-synced agent workflow work there.

| Capability | Claude Code | claude.ai |
|---|---|---|
| Skills from git | ✅ auto-discovered | ❌ manual `.zip`, account-wide |
| Subagents | ✅ | ❌ not available |
| `CLAUDE.md` | ✅ | ❌ global custom instructions only |
| Plugin marketplace | ✅ | ⚠️ manual install |
| GitHub sync | ✅ native | ❌ none |

**Claude Code is the platform for this workflow.** If your team needs the claude.ai web UI, the honest answer is that the spec template and thresholds transfer as reference documents, but the enforcement does not.

**It does not run your CI.** The skills invoke the commands in `agentic.config.yaml` locally and read the exit codes. Wire the same commands into your CI as the backstop — belt and braces, deliberately.

**It does not enforce the pre-push hook for you.** The design calls for a hook reading `agentic.config.yaml` so an agent structurally cannot commit past a failing check. Installing that hook is a repo-level task the Config Agent will remind you about but cannot do unattended — it's a change to your git config, and that should be your call.

**Multi-repo handoffs are manual by design.** When frontend and backend live in separate repos, a human copies the `ApiContract` across. No polling, no webhooks, no heartbeat service. That's a deliberate trade: it gives up automatic staleness detection in exchange for needing zero infrastructure.

**Twelve decisions are deliberately left open.** Things like PO response-time SLAs and who grants debt waivers are organizational, not technical. They're enumerated in the workflow document's escalation table rather than papered over with a default that would be wrong for most teams.

---

## Further reading

- [`agentic-first-sdlc-workflow.md`](agentic-first-sdlc-workflow.md) — full design, the 8-persona debate that produced it, and every threshold's rationale
- [`insights-synthesis.md`](insights-synthesis.md) — the research this is built on
- [`workflow-improvements-consensus.md`](workflow-improvements-consensus.md) — adversarial review of the design itself

## License

MIT
