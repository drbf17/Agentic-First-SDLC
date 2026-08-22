# Project instructions

<!--
Copy into the root CLAUDE.md of any repo using the Agentic-First SDLC.
Keep it short — CLAUDE.md loads on every turn. Detail belongs in the skills,
which load only when relevant.
-->

## How work flows here

This repository follows a spec-driven pipeline. Non-trivial feature work goes through it rather than being coded ad hoc. Invoke the `agentic-sdlc` skill to route to the right stage, or name a stage directly.

**The pipeline in one line:**
`config-bootstrap` (once per repo) → `spec-judge` (seal the spec) → build agents in parallel → `verify-gate` → `ship-release` → a human merges.

## Non-negotiables

1. **No `agentic.config.yaml`, no pipeline.** If it's missing at the repo root, run `config-bootstrap` before anything else. If its hash changed mid-task, halt and re-read.
2. **Deterministic checks beat instructions.** Never put a quality rule in a prompt when it could be an exit code. Every blocking check in `agentic.config.yaml` must exit 0 before any commit — this is enforced by a hook, not by good intentions.
3. **Sealed specs are immutable.** There is no un-seal. Amendments are delta specs chained by `parent_hash`.
4. **Never a silent assumption.** An unanswerable question shrinks scope into `deferred_decisions` with an owner, a default, and an expiry.
5. **Agents never merge.** Push to `feature/<spec-id>`; a human merges.
6. **Security BLOCK has no override** — not by a sealed spec, not by a deadline.
7. **Tests come from the spec, never from the implementation.** A test asserting what the code already does is not a test.

## Small changes

A typo fix or a one-line copy change does not need a sealed spec. Use judgment: if it touches auth, money, data shape, or an irreversible action, it goes through the pipeline regardless of size.

<!-- Add project-specific context below: domain glossary, architecture notes, gotchas. -->
