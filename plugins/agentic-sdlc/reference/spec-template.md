# PO Spec Template — Stage 0

Copy this file, fill in every field, save as `/agent-handoffs/specs/<spec_id>/<spec_id>.v0.raw.md`.

**Submit it as a file, not as a chat message.** Free text and missing required fields are rejected by a parser check before any model reads it — that rejection costs you nothing and consumes no grilling iteration, but a vague spec that slips through costs the whole team a rework cycle.

Leave `existing_figma` blank if there is no design yet; that triggers the Prototyping Agent rather than an error.

---

```markdown
---
spec_id: ""                          # kebab-case, unique. e.g. "checkout-guest-flow"
title: ""
change_type: ""                      # REQUIRED: "feature" | "bugfix" | "hotfix"
                                     # drives which branch type Stage 3 creates and what
                                     # base branch it starts from — see reference/config-schema.md

actors:
  - name: ""                         # who acts. e.g. "Guest shopper"
    auth: ""                         # REQUIRED: authn + authz. "unauthenticated, session cookie only"

happy_path:
  - step: ""                         # each step needs >=1 matching acceptance criterion

acceptance_criteria:
  - given: ""
    when: ""
    then: ""

nfrs:
  - metric: ""                       # e.g. "p95 latency", "concurrent users"
    value: ""                        # MUST be a number + unit. "300ms", "500 rps".
                                     # "fast", "scalable", "responsive" are rejected.

out_of_scope:
  - ""                               # real exclusions. Empty on a non-trivial spec
                                     # means the boundary was never considered.

dependencies:
  - ""                               # for each, you will be asked: what happens when it
                                     # is slow, errors, or is entirely unavailable?

existing_figma: ""                   # leave blank to trigger the Prototyping Agent

data_touched:
  - field: ""
    pii: false                       # true ⇒ OWASP Top 10 checklist becomes mandatory
    classification: ""               # e.g. "public", "internal", "PII", "PCI"

# Optional — only when Frontend and Backend live in SEPARATE repositories.
# Omit or set enabled: false for a single-repo project.
repo_boundaries:
  enabled: false
  handoff_directory: "/agent-handoffs"   # must be identical in both repos
  frontend:
    repo: ""                         # e.g. "org/frontend-repo"
    assignee: ""
    owns_paths: []                   # e.g. ["src/components/**", "src/pages/**"]
  backend:
    repo: ""
    assignee: ""
    owns_paths: []                   # e.g. ["src/api/**", "migrations/**"]
---

# Problem Statement

What problem does this solve, for whom, and how will we know it worked?

# Notes

Anything else — links, prior art, constraints, open questions you already know about.
```

---

## What happens next

The Tech Lead Agent will interrogate this spec for **up to 5 iterations**. Expect questions about:

1. Happy-path steps with no acceptance criterion
2. Actors with no auth story
3. Unquantified NFRs
4. Edge cases — derived systematically from *actor states × input boundaries × dependency failure modes*
5. PII accuracy
6. An empty or unconsidered `out_of_scope`
7. Behavior when each dependency is slow, errors, or is unavailable
8. Missing UI reference for a user-facing flow

**Every question is answerable with a concrete value, a named entity, or a yes/no.** If you genuinely cannot answer one, say so — the scope shrinks and the open item is logged with an owner, a conservative default, and an expiry. That is a supported outcome, not a failure. What is *not* supported is a silent assumption: the agents downstream cannot ask you anything, so an unanswered question becomes a guess baked into production code.

The spec seals when average ambiguity is **< 0.15** and no single item exceeds **0.4**. At 5 iterations without convergence, it escalates to a human Tech Lead rather than force-sealing.
