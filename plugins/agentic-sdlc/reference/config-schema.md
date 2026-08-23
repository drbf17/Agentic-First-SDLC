# Reference — `agentic.config.yaml` schema

Lives at the **repository root**, beside `package.json` / `tsconfig.json` — *not* inside `/agent-handoffs`. It is repo-scoped rather than spec-scoped: it must be readable before any spec exists, it changes on a different cadence, and engineers expect toolchain config at the root.

## Complete annotated example

```yaml
schema_version: "1.0"
artifact_type: RepoVerificationConfig
content_hash: "sha256:a3f2..."        # over the `checks` block; dev agents pin to this
produced_by:
  agent: "config-agent"
  repo: "org/backend-repo"
  run_id: "0f8c-..."
  model_version: "<model that conducted the interrogation>"
produced_at: "2026-08-22T14:00:00Z"
approved_by: "engineer@example.com"    # a HUMAN, always. Never blank, never an agent.

payload:
  runtime:
    package_manager: "pnpm"
    node_version: "22.x"

  git:
    workflow: "gitflow"              # gitflow (default) | trunk-based — see below
    default_branch: "main"           # trunk-based base; also gitflow's `main`
    develop_branch: "develop"        # gitflow only. Omit/ignore under trunk-based.
    remote_provider: "github"        # default and only provider the bundled github-pr skill drives
    commit_convention: "conventional-commits"   # fixed — see backend-dev/frontend-dev/qa-engineer
    merge_strategy: "squash"         # squash (default/preferred) | merge | rebase

  checks:
    - id: lint
      category: lint                   # lint|typecheck|static|sast|format|deps|build|test
      command: "pnpm eslint . --max-warnings=0"
      pass_when: "exit_code == 0"
      enforcement: blocking            # blocking | report-only
      scope: changed-files             # changed-files | whole-repo
      runs_in: [dev-loop, pre-push, gate]
      verified_at: "2026-08-22T14:00:00Z"   # proof the Config Agent ran it successfully
      typical_duration_seconds: 12

    - id: typecheck
      category: typecheck
      command: "pnpm tsc --noEmit"
      pass_when: "exit_code == 0"
      enforcement: blocking
      scope: whole-repo                # type errors are non-local by nature
      runs_in: [dev-loop, pre-push, gate]
      verified_at: "2026-08-22T14:00:00Z"
      typical_duration_seconds: 34

    - id: static-analysis
      category: static
      command: "sonar-scanner -Dsonar.qualitygate.wait=true"
      pass_when: "exit_code == 0"      # quality-gate failure returns non-zero
      enforcement: blocking
      scope: whole-repo
      runs_in: [pre-push, gate]        # too slow for every dev-loop iteration
      verified_at: "2026-08-22T14:00:00Z"
      typical_duration_seconds: 95

    - id: sast
      category: sast
      command: "semgrep --config auto --error --quiet"
      pass_when: "exit_code == 0"
      enforcement: blocking
      scope: changed-files
      runs_in: [dev-loop, pre-push, gate]
      verified_at: "2026-08-22T14:00:00Z"
      typical_duration_seconds: 18

  waivers: []
```

## Field reference

| Field | Required | Notes |
|---|---|---|
| `id` | yes | unique within the file |
| `category` | yes | `lint` · `typecheck` · `static` · `sast` are the four **mandatory** categories. `format` · `deps` · `build` · `test` are optional. |
| `command` | yes | exact, runnable. Must have been executed successfully at least once — see `verified_at`. |
| `pass_when` | yes | normally `exit_code == 0` |
| `enforcement` | yes | `blocking` blocks commits and gates. `report-only` runs, logs, and surfaces on the Stage 8 scorecard, but blocks nothing. |
| `scope` | yes | `changed-files` keeps fast checks fast; `whole-repo` for non-local analysis |
| `runs_in` | yes | any of `dev-loop`, `pre-push`, `gate`. **Every blocking check must include `gate`.** |
| `verified_at` | yes | timestamp of a successful invocation by the Config Agent. **No `verified_at` ⇒ the check is invalid and must not be written.** |
| `typical_duration_seconds` | yes | measured, not estimated. Drives `runs_in` assignment. |

## `payload.git` — chosen git workflow

Set **once**, at bootstrap, alongside the four check categories — not per spec. Every downstream skill and agent reads this instead of assuming GitFlow.

| Field | Required | Notes |
|---|---|---|
| `workflow` | yes | `gitflow` (default) or `trunk-based`. See comparison below. |
| `default_branch` | yes | The trunk. `main` in both workflows. |
| `develop_branch` | gitflow only | Integration branch feature/bugfix work targets. Ignored under `trunk-based` — there is no develop. |
| `remote_provider` | yes | `github` is the default and the only value the bundled `github-pr` skill drives today. A different value means PR creation/merge must be done by hand or a custom skill. |
| `commit_convention` | yes | Fixed to `conventional-commits`. Every agent commit message, and every PR title (which becomes the squash-merge commit message), follows `type(<spec_id>): summary` — see [skills/github-pr](../skills/github-pr/SKILL.md). |
| `merge_strategy` | yes | `squash` is the SDLC's default and preferred value — one atomic commit per spec increment on `develop`/`main`. `merge` and `rebase` are supported for teams that want full sub-agent commit history preserved. |

### `gitflow` (default)

```
feature/<spec_id>   ← change_type: feature — branched from develop
bugfix/<spec_id>    ← change_type: bugfix  — branched from develop
hotfix/<spec_id>    ← change_type: hotfix  — branched from main
```

`feature/*` and `bugfix/*` merge to `develop_branch`; `hotfix/*` merges to `main` (and is back-merged to develop by the human release process). See [skills/ship-release](../skills/ship-release/SKILL.md).

### `trunk-based`

```
feature/<spec_id>   ← change_type: feature — branched from default_branch
bugfix/<spec_id>    ← change_type: bugfix  — branched from default_branch
hotfix/<spec_id>    ← change_type: hotfix  — branched from default_branch
```

No `develop`, no `release/*`. Every branch is short-lived and branches from — and merges directly (squash, by default) back into — `default_branch`. The prefix still encodes intent for `git log`/PR triage even though the base branch never varies.

Either way, **`default_branch`/`develop_branch` are only ever updated via a pull request**, after all verdicts are green — never a direct push, from an agent or otherwise.

## `runs_in` budgets

| Value | Runs | Budget |
|---|---|---|
| `dev-loop` | every write-verify cycle inside a build agent's loop | **< ~30s.** Never exceed ~60s — the loop becomes unusable and the team disables it. |
| `pre-push` | once, before a commit is permitted | slower whole-repo analysis lives here |
| `gate` | re-run at Stages 4–6 against the merge candidate | required minimum for every blocking check |

## Waivers

A mandatory category may be skipped **only** with all three fields present:

```yaml
  waivers:
    - category: static
      reason: "No SonarQube instance provisioned for this repo yet"
      granted_by: "engineer@example.com"   # a named human. Never an agent, never "the team".
      expires_at: "2026-10-01"             # mandatory. There are no permanent waivers.
```

**An expired waiver is treated as a failing check**, not a warning — the same treatment expired security WARNs get at the `release/*` cut. A waiver missing any of the three fields is invalid and the config must not load.

## Suggested commands by stack

| Stack | lint | typecheck | static | sast |
|---|---|---|---|---|
| TypeScript / Node | `eslint . --max-warnings=0` | `tsc --noEmit` | `sonar-scanner` | `semgrep --config auto --error` |
| Python | `ruff check` | `mypy .` or `pyright` | `sonar-scanner` | `semgrep --config auto --error`, `bandit -r .` |
| Go | `golangci-lint run` | (compiler) `go vet ./...` | `sonar-scanner` | `gosec ./...`, `semgrep` |
| Java / Kotlin | `./gradlew ktlintCheck` | (compiler) `./gradlew compileJava` | `./gradlew sonar` | `semgrep`, CodeQL |
| Rust | `cargo clippy -- -D warnings` | `cargo check` | `sonar-scanner` | `cargo audit`, `semgrep` |

**Prefer off-the-shelf tooling over anything custom.** Every category is satisfied by mature, free, widely-deployed tools. Custom verification is a maintenance liability and a poor use of engineering time.
