# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Org-as-code for the `millsymills-com` GitHub organization. OpenTofu declares org settings, org-wide rulesets, and per-repo settings for every repo in the org — including this management repo itself. PR → `tofu plan` (reader App, AWS OIDC); merge to `main` → `tofu apply` (writer App, AWS OIDC); nightly `tofu plan -detailed-exitcode` for drift.

Design spec: `docs/superpowers/specs/2026-05-09-millsymills-org-design.md`. Plan-1 completion notes: `docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md` — read these before making non-trivial changes; they record deviations from the spec and what's been deliberately deferred.

Plan-2 ADRs Accepted 2026-05-15:

- **ADR-0001** — `docs/adr/0001-gate-bypass-mitigation.md`. `workflow_run` mitigation for PR-modifiable gate bypass (issue #13). Impl LIVE via `.github/workflows/gate-verified.yml`. Rollout step 2 (additive `gate-verified` required check) is issue #34; step 3 (drop `gate`) is issue #35.
- **ADR-0002** — `docs/adr/0002-required-signed-tag-check.md`. Workflow-mediated signed-tag push (issue #22). Impl tracked as a three-PR rollout in issue #36; not yet started.

Plan-2 portfolio rollout spec drafted at `docs/superpowers/specs/2026-05-14-millsymills-portfolio-content.md`; gated on ADRs 0003-0006 (issue #46).

## Change flow

PR opens → `tofu-plan` runs (reader App, plan-only OIDC role pinned to the `tofu-plan` GitHub environment) → `gate` synthesizer job encodes "validate must succeed; plan must succeed on internal PRs or be skipped on fork PRs" and is the in-PR required check → `gate-verified.yml` re-asserts `gate` succeeded from `main`'s default-branch context via `workflow_run` and posts a tamper-proof `gate-verified` check (rolled into the required-check set additively per ADR-0001) → ruleset gates merge → `tofu-apply` runs on `main` (writer App, apply OIDC role pinned to `tofu-apply.yml@refs/heads/main`) → nightly `tofu-drift` with `-detailed-exitcode` opens an issue on non-zero.

## Architecture

- **State backend** — S3 bucket `tfstate-millsymills-025507317036` in `us-west-1`, KMS-encrypted (`alias/tfstate-millsymills`), native S3 locking (`use_lockfile`). AWS account `025507317036`.
- **Identities** — two GitHub Apps (`millsymills-org-bot-writer`, `millsymills-org-bot-reader`); private keys live only in AWS Secrets Manager and are fetched to `${RUNNER_TEMP}` at `0600` for each workflow run. Three OIDC-trusted IAM roles: `gha-millsymills-org-tofu-{plan,apply,drift}`, each pinned to its workflow+environment. The reader App needs `organization_administration: write` despite being plan-only — `github_organization_ruleset` refresh hits `GET /orgs/{org}/rulesets/{id}` which silently requires `:write` on that endpoint.
- **Top-level composition** —
  - `org.tf` instantiates `org-baseline` + the two org rulesets (`ruleset-default-branch`, `ruleset-tag-protection`).
  - `repos_existing.tf` instantiates `repo-baseline` for every existing org repo *except* this one. Adding `millsymills-com-org` here would double-manage state — there's an inline comment marking it.
  - `repos_meta.tf` imports + manages this management repo, declares its `tofu-plan` / `tofu-apply` / `tofu-drift` environments, and applies the per-repo required-status-checks ruleset.
- **Modules** live under `modules/`: `org-baseline`, `repo-baseline`, `ruleset-default-branch`, `ruleset-tag-protection`. Each has its own `tests/*.tftest.hcl` using `mock_provider "github"`.
- **`bootstrap/`** is one-time AWS provisioning (S3/KMS/IAM/Secrets Manager) plus the GitHub-App creation runbook. **Sealed**: `bootstrap/.disabled` is present, so `aws-bootstrap.sh` refuses to run without `--force`. Bats tests live in `bootstrap/tests/`.

## Self-managing repo, important consequences

- `tofu-plan.yml` deliberately has **no `paths:` filter** — the management repo's required-check ruleset requires the `gate` job to report on every PR, so doc-only PRs would otherwise deadlock the ruleset.
- The required check `gate` is a synthesizer job (`if: always()`) that encodes "validate must succeed; plan must succeed on internal PRs or be skipped on fork PRs." This closes GitHub's "skipped == passing" loophole. Don't replace it with raw `plan` as a required check, and don't refactor it to use early-exit semantics that change skip-vs-success behavior.
- `gate-verified.yml` runs on `main` only, listens to `workflow_run` completions of `tofu`, and posts a `gate-verified` check-run after asserting the in-run `gate` job succeeded. This closes the PR-modifiable-workflow bypass — a PR cannot edit a default-branch-only workflow. ADR-0001 captures the threat model; do not move the logic back into `tofu-plan.yml` or weaken the `select(.name == "gate") | .conclusion == "success"` assertion.
- Ruleset required-check **contexts are job names**, not `"<workflow> / <job>"`: `gate`, `zizmor`, `gitleaks`, `actionlint`, `analyze (actions)`. GitHub's check-runs API surfaces only the job name, which is what ruleset matching compares against. Verified empirically in PR #28 against the head commits of PRs #14 and #17.
- Org rulesets are currently `enforcement = "evaluate"` (dry-run). The flip to `"active"` is intentionally deferred until ~2026-05-18 after an observation window. Don't flip silently as part of an unrelated change.
- The management repo's `tofu-plan` OIDC trust is loosened to `tofu-plan.yml@*` because PR refs are `refs/pull/N/merge`; apply/drift stay pinned to `main`. The `repository_owner_id` trust condition was dropped from all three live role trust policies — it silently rejects on this GitHub OIDC provider; `sub` + `repository_id` are used instead. The bootstrap script still emits the rejected shape; treat that as known drift until bootstrap is rewritten.

## Workflows

Ten workflows under `.github/workflows/`: `tofu-plan`, `tofu-apply`, `tofu-drift` (the load-bearing OpenTofu pipeline); `gate-verified` (ADR-0001 mitigation); `release` (post-push tag-signature audit; becomes audit-only once ADR-0002 impl ships); `actionlint`, `codeql`, `gitleaks`, `scorecard`, `zizmor` (supply-chain + workflow security baseline). All inherit the same hardening conventions documented below.

## Common commands

Tool versions are pinned in `.tool-versions` (use `mise`/`asdf`): `opentofu 1.10.3`, `tflint 0.55.1`, `shellcheck 0.10.0`, `bats 1.11.1`.

```bash
# Format / lint / validate the OpenTofu config
tofu fmt -check -recursive
tofu init -backend=false -input=false   # local; no AWS needed
tofu validate
tflint --init && tflint --recursive --format=compact

# Run all module tests (mock_provider, no API calls)
tofu test
# Run a single module's tests
tofu test -filter=modules/org-baseline/tests/baseline.tftest.hcl

# Bootstrap script tests
bats bootstrap/tests/
bats bootstrap/tests/test_disabled_guard.bats   # single file

# Workflow linters (local parity with CI)
actionlint .github/workflows/
zizmor .github/workflows/

# Pre-commit hooks (gitleaks, shellcheck, tofu fmt, tflint, actionlint, ...)
pre-commit install
pre-commit run --all-files
```

A real `tofu plan` requires (a) an AWS identity that can read state + KMS-decrypt + read the App PEM in Secrets Manager, and (b) `TF_VAR_github_app_id` / `TF_VAR_github_app_installation_id` / `TF_VAR_github_app_pem_file`. The local `mills` IAM user is intentionally `ReadOnlyAccess` and is **denied** KMS:Decrypt on the state bucket key, so `tofu state list` from a dev machine returns AccessDenied — by design. The recipe to fetch the reader App PEM to a 0600 tempfile is in `terraform.tfvars.example`.

## Operational guardrails

- **Do not run `tofu apply` from a dev machine.** All changes go through PR → CI plan → merge → CI apply. The local AWS identity can't apply anyway; the guardrail is also documented in `bootstrap/README.md`.
- **Do not re-run `bootstrap/aws-bootstrap.sh`** without a strong reason and `--force`. It is destructive-adjacent (recreates IAM/secrets) and is sealed by `bootstrap/.disabled`.
- **Do not add `head_ref` to the org's OIDC sub-claim template** (`bootstrap/github-bootstrap.md` step 1). The IAM trust policies match on the full `sub`; adding `head_ref` reshapes it and breaks every role.
- **`advanced_security` is intentionally absent / `false`.** This org is on Free; GitHub silently ignores writes that try to enable GHAS, producing perpetual plan drift. zizmor-action runs with `advanced-security: false` for the same reason.
- **Solo-owner caveat.** `require_code_owner_review` and `require_last_push_approval` are off in the default-branch ruleset; enabling them would deadlock every owner-authored PR including this repo's own apply pipeline.
- **Four org settings are unmanaged by the provider** (`members_can_delete_repositories`, `members_can_change_repo_visibility`, `members_can_invite_outside_collaborators`, `members_can_delete_issues`). They live in `scripts/set-extra-org-settings.sh` and must be set via the org's web UI; the script reads current state and flags drift.

## GitHub Actions conventions

All `uses:` are pinned to a full commit SHA with a `# vX.Y.Z` comment. Every `actions/checkout` uses `persist-credentials: false`. Every job starts with `step-security/harden-runner` — `egress-policy: block` plus an explicit allowlist for credentialed jobs, `audit` for uncredentialed ones. New egress endpoints must be added to every credentialed workflow's allowlist (they are duplicated by design — see the allowlist blocks in `tofu-plan.yml`, `tofu-apply.yml`, `tofu-drift.yml`).

When bumping action versions, look up the current stable release; several have already been bumped beyond the design spec for security/compatibility reasons recorded in the Plan-1 completion notes.

## Governance + security policy

- **`CODEOWNERS`** assigns `*` to `@millsmillsymills`. Solo-owner posture; review-headcount-based gates (`require_code_owner_review`, `require_last_push_approval`) stay off in the default-branch ruleset for the same reason — re-enable only after a second maintainer joins.
- **`SECURITY.md`** routes vulnerability reports through GitHub Security Advisories on this repo, not public issues. 5-business-day initial response, 90-day coordinated disclosure.

## Agent skills

- **Issue tracker** — GitHub Issues at `millsymills-com/millsymills-com-org`. See `docs/agents/issue-tracker.md`.
- **Triage labels** — canonical five labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.
- **Domain docs** — single-context layout: `docs/adr/` (in use; currently holds ADR-0001 + ADR-0002) plus a `CONTEXT.md` at repo root if a future ADR introduces one. See `docs/agents/domain.md`.
