# Architecture Proposal Template — Stage 1.5 (optional)

Copy this file, fill in every field, save as `/agent-handoffs/architecture/<spec_id>.v0.raw.md` — or, for a decision not tied to one spec, `/agent-handoffs/architecture/<decision_id>.v0.raw.md`.

Same rule as the spec template: **submit it as a file, not a chat message.** Free text or missing required fields are rejected before grilling starts and cost you no iteration.

---

```markdown
---
decision_id: ""                      # kebab-case, unique. e.g. "async-order-events"
spec_id: ""                          # the spec that triggered this, if any — blank for a standalone decision
title: ""
driver: ""                           # REQUIRED — the specific thing forcing this decision.
                                     # Copy it from spec-judge's architecture_recommendation.drivers
                                     # if this came from a seal, e.g. "new datastore: needs a queue,
                                     # nothing async exists in this repo yet"

components:
  - name: ""                         # a new or changed component/service/module
    responsibility: ""               # what it owns — and, implicitly, what it does NOT own

data_flow: ""                        # how data moves through the new/changed components,
                                     # including what's synchronous vs. async

failure_modes:
  - scenario: ""                     # e.g. "queue consumer is down for 10 minutes"
    behavior: ""                     # required behavior, not "handle gracefully"

scaling_limits:
  - dimension: ""                    # e.g. "messages/sec", "concurrent connections"
    ceiling: ""                      # a number. "should scale fine" is rejected, same as an NFR.

alternatives_considered:
  - option: ""
    rejected_because: ""             # a real reason, not "team preference"

migration_and_rollback: ""           # how you get from current state to this, and how you back out
                                     # if it's wrong — required for anything touching existing data

operational_cost: ""                 # new on-call surface, new infra to run, new failure class
                                     # the team didn't have before
---

# Context

What's driving this decision — link back to the spec or the recurring problem, if there is one.

# Notes

Anything else — prior art, constraints, links.
```

---

## What happens next

`architecture-judge` interrogates this proposal for **up to 5 iterations**, the same adversarial stance and the same ambiguity math `spec-judge` uses (avg < 0.15, max item ≤ 0.4). Expect pressure on:

1. Components with a stated responsibility but no stated non-responsibility (scope creep waiting to happen)
2. Data flow steps with no failure mode defined
3. Scaling limits given as adjectives instead of numbers
4. Alternatives listed without a real reason for rejection
5. Any touch on existing data with no migration/rollback story

This is **optional and human-invoked only** — nothing in the pipeline blocks on it. It exists for the cases where a spec's `architecture_recommendation` flagged `requires_review`, or where an architect/tech lead wants their own design grilled before agents build against it.
