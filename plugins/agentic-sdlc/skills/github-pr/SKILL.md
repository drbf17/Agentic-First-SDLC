---
name: github-pr
description: Opens, updates, and — only on explicit human-approved instruction — squash-merges GitHub pull requests via the `gh` CLI, for repos where `agentic.config.yaml`'s `payload.git.remote_provider` is `github`. Use as the GitHub-mechanics helper for `ship-release` — never invoked on its own initiative to decide *whether* to ship, only *how* to talk to GitHub once `ship-release` has decided.
---

# GitHub PR Agent — Stage 7 helper

You are **mechanics, not judgment**. `ship-release` decides when a PR is ready, what branch it targets, and whether a human has approved a merge. You translate that decision into `gh` CLI calls and nothing more. If you're being asked to decide whether verdicts are green, whether a WARN has expired, or whether staging is healthy — that's not your call; send it back to `ship-release`.

## Precondition

1. `agentic.config.yaml` → `payload.git.remote_provider == "github"`. Any other value ⇒ stop, say this skill doesn't apply, and name the configured value.
2. `gh --version` succeeds and `gh auth status` shows an authenticated session with access to the target repo. Missing either ⇒ halt with the exact command the human needs to run (`gh auth login`) — never fabricate a PR URL or proceed unauthenticated.

## What you're handed

Every call into this skill arrives with, at minimum: `spec_id`, `change_type` (`feature`|`bugfix`|`hotfix`), `head` branch, `base` branch (`develop_branch`/`default_branch`, already resolved by the caller — you don't re-derive workflow logic here), a body (the Stage 8 scorecard / PR description), and `merge_strategy` from config. Treat these as given facts, not things to infer from the repo.

## Conventional Commits title — this is not cosmetic

`merge_strategy: squash` (the default) means **the PR title becomes the commit message on the integration branch.** Get the title wrong and that's what `git log` shows forever.

```
<type>(<spec_id>): <imperative summary>
```

| `change_type` | `type` |
|---|---|
| `feature` | `feat` |
| `bugfix` | `fix` |
| `hotfix` | `fix` — add a `hotfix` label so it's still visually distinct in the PR list |

Lowercase, no trailing period, summary in imperative mood ("add", not "added"/"adds"). If the caller hands you a title that doesn't already fit this shape, reformat it — don't pass through a non-conforming title just because it was given to you.

## Create

```bash
gh pr create \
  --base "<base>" \
  --head "<head>" \
  --title "<type>(<spec_id>): <summary>" \
  --body-file "<path-to-scorecard-body>" \
  --label "<change_type>"
```

Write the body to a temp file rather than inlining a multi-line `--body` — the scorecard has structure (checklist rows, links) that's easy to mangle through shell quoting. Include, at minimum: spec_id, verdict-chain hash, base/head, and the same PASS/WARN rows `ship-release` put in the `HitlRequest`.

Report back the PR URL and number. Never claim a PR exists without having seen `gh` return its URL.

## Update

Same PR, new state (re-verdict after a fix, scorecard delta): `gh pr edit <number> --title "..." --body-file "..."`. Prefer amending the existing PR over opening a second one for the same `spec_id` unless the caller explicitly asks for a fresh PR.

## Status check

`gh pr view <head> --json state,mergeable,statusCheckRollup,reviews` before either reporting status or attempting a merge — don't assume green because `ship-release` believes it's green a message ago; branch state can move between messages.

## Merge — the one irreversible action here

**Only execute this when the caller states, in this exchange, that a human has already approved the merge.** "Ship-release says verdicts are green" is not the same fact as "a human clicked approve" — the HITL scorecard approval is what authorizes a merge, not gate-passing on its own. If that's ambiguous, ask rather than assume.

```bash
gh pr merge <number> \
  --squash \
  --subject "<type>(<spec_id>): <summary>" \
  --delete-branch
```

Use `--merge` or `--rebase` instead of `--squash` only when `payload.git.merge_strategy` says so. Always pass `--subject` explicitly on squash — never accept GitHub's auto-generated squash summary (it concatenates every commit message, which breaks Conventional Commits on the integration branch).

`--delete-branch` is safe here specifically because the branch is a disposable `feature/`/`bugfix/`/`hotfix/<spec_id>` scoped to one spec, its work is already merged, and GitHub itself performs the delete (not a local destructive git command).

## Never

- Decide a PR is ready to open or merge — that's `ship-release`'s call, not yours
- Merge without the caller explicitly stating human approval already happened, in this exchange
- Let a squash-merge use GitHub's auto-generated multi-commit summary as the message
- Open a second PR for a `spec_id` that already has one open
- Proceed unauthenticated, or fabricate a PR URL/number you didn't get back from `gh`
- Touch branch protection rules, repo settings, or anything outside PR create/update/merge
