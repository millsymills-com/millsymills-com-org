# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Org-as-code for the `millsymills-com` GitHub organization. OpenTofu declares org settings, org-wide rulesets, and per-repo settings for every repo in the org — including this management repo itself. PR → `tofu plan` (reader App, AWS OIDC); merge to `main` → `tofu apply` (writer App, AWS OIDC); nightly `tofu plan -detailed-exitcode` for drift.

Design spec: `docs/superpowers/specs/2026-05-09-millsymills-org-design.md`. Plan-1 completion notes: `docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md` — read these before making non-trivial changes; they record deviations from the spec and what's been deliberately deferred.

Plan-2 ADRs Accepted 2026-05-15:

- **ADR-0001** — `docs/adr/0001-gate-bypass-mitigation.md`. `workflow_run` mitigation for PR-modifiable gate bypass (issue #13). Impl LIVE via `.github/workflows/gate-verified.yml`. Rollout complete: step 2 (add `gate-verified` alongside `gate`) landed in PR #52, and step 3 (drop `gate`) landed in PR #65, closing issue #35. The live ruleset requires `actionlint`, `analyze (actions)`, `gate-verified`, `gitleaks`, `zizmor` — `gate` still runs as a job but is no longer required. Codex adversarial review on #52 surfaced that gate-verified only catches the skip/rename/missing-conclusion class; the stub-with-success residual is documented in ADR-0001 *What `gate-verified` catches and does not catch* and tracked separately in issue #53.
- **ADR-0002** — `docs/adr/0002-required-signed-tag-check.md`. Workflow-mediated signed-tag push (issue #22). Impl tracked as a three-PR rollout in issue #36; not yet started.

Plan-2 portfolio rollout spec drafted at `docs/superpowers/specs/2026-05-14-millsymills-portfolio-content.md`; gated on ADRs 0003-0006 (issue #46).

- **ADR-0007** — `docs/adr/0007-renovate-over-dependabot.md`. Proposed 2026-08-21. Renovate will replace Dependabot for version updates across both accounts (Dependabot *alerts* stay); shared preset at `millsymills-com/.github` → `renovate-config.json`; automerge bounded below the major boundary. Carries the `repo-baseline` change to squash-only + auto-merge capability. No repo extends the preset yet — onboarding is per-repo and follows.

## Change flow

PR opens → `tofu-plan` runs (reader App, plan-only OIDC role pinned to the `tofu-plan` GitHub environment) → `gate` synthesizer job encodes "validate must succeed; plan must succeed on internal PRs or be skipped on fork PRs" → `gate-verified.yml` re-asserts `gate` succeeded from `main`'s default-branch context via `workflow_run` and posts a `gate-verified` check (the required one since PR #65 dropped `gate` per ADR-0001 step 3 — closes the skip/rename/missing-conclusion bypass class, not stub-with-success; stub-with-success residual tracked in issue #53) → ruleset gates merge → `tofu-apply` runs on `main` (writer App, apply OIDC role pinned to `tofu-apply.yml@refs/heads/main`) → nightly `tofu-drift` with `-detailed-exitcode` opens an issue on non-zero.

## Architecture

- **State backend** — S3 bucket `tfstate-millsymills-025507317036` in `us-west-1`, KMS-encrypted (`alias/tfstate-millsymills`), native S3 locking (`use_lockfile`). AWS account `025507317036`.
- **Identities** — two GitHub Apps (`millsymills-org-bot-writer`, `millsymills-org-bot-reader`); private keys live only in AWS Secrets Manager and are fetched to `${RUNNER_TEMP}` at `0600` for each workflow run. Three OIDC-trusted IAM roles: `gha-millsymills-org-tofu-{plan,apply,drift}`, each pinned to its workflow+environment. The reader App needs `organization_administration: write` despite being plan-only — `github_organization_ruleset` refresh hits `GET /orgs/{org}/rulesets/{id}` which silently requires `:write` on that endpoint.
- **Top-level composition** —
  - `org.tf` instantiates `org-baseline` + the two org rulesets (`ruleset-default-branch`, `ruleset-tag-protection`).
  - `repos_existing.tf` instantiates `repo-baseline` for every existing **public** org repo except this one. Adding `millsymills-com-org` here would double-manage state — there's an inline comment marking it. Two private org repos are deliberately absent: a declaration needs name + description, and this repo is public, so managing them would publish a private repo's name. See ADR-0007; the posture decision is the unfiled ADR-0004 (issue #46).
  - `repos_meta.tf` imports + manages this management repo, declares its `tofu-plan` / `tofu-apply` / `tofu-drift` environments, and applies the per-repo required-status-checks ruleset.
- **Modules** live under `modules/`: `org-baseline`, `repo-baseline`, `ruleset-default-branch`, `ruleset-tag-protection`. Each has its own `tests/*.tftest.hcl` using `mock_provider "github"`.
- **`bootstrap/`** is one-time AWS provisioning (S3/KMS/IAM/Secrets Manager) plus the GitHub-App creation runbook. **Sealed**: `bootstrap/.disabled` is present, so `aws-bootstrap.sh` refuses to run without `--force`. Bats tests live in `bootstrap/tests/`.

## Self-managing repo, important consequences

- `tofu-plan.yml` deliberately has **no `paths:` filter** — `gate-verified` is a required check and only fires off a completed `tofu` workflow run, so a doc-only PR that skipped `tofu-plan` would never get the check and would deadlock the ruleset.
- The required check `gate` is a synthesizer job (`if: always()`) that encodes "validate must succeed; plan must succeed on internal PRs or be skipped on fork PRs." This closes GitHub's "skipped == passing" loophole. Don't replace it with raw `plan` as a required check, and don't refactor it to use early-exit semantics that change skip-vs-success behavior.
- `gate-verified.yml` runs on `main` only, listens to `workflow_run` completions of `tofu`, and posts a single combined `gate-verified` check-run after running two checks: (1) the `gate` job in the triggering run concluded `success`; (2) `.github/workflows/tofu-plan.yml` blob SHA matches `main`, OR the open PR for the head SHA carries the `workflow-update` label. A PR cannot edit a default-branch-only workflow, so the verifier itself is tamper-proof. Combined scope: catches rename/delete/skip/non-success of the `gate` job (check 1) AND PR-side modifications to `tofu-plan.yml` without an explicit maintainer-applied `workflow-update` label (check 2 — closes the ADR-0001 stub-with-success residual). The residual is now bounded to PRs a maintainer has deliberately labeled. See ADR-0001 *What `gate-verified` catches and does not catch* + *Operational mechanics — `workflow-update` label*. Do not move the logic back into `tofu-plan.yml`, do not weaken either assertion, and do not rename the in-workflow `gate` job (the assertion matches on that exact name). Re-evaluation after applying the label requires a fresh `tofu` workflow run (push an empty commit or rerun the latest tofu run) because `workflow_run` does not refire on `pull_request: labeled`.
- Ruleset required-check **contexts are job names**, not `"<workflow> / <job>"`: `gate-verified`, `zizmor`, `gitleaks`, `actionlint`, `analyze (actions)`. GitHub's check-runs API surfaces only the job name, which is what ruleset matching compares against. Verified empirically in PR #28 against the head commits of PRs #14 and #17.
- Org rulesets (`default-branch-protection`, `tag-protection`) are `enforcement = "active"`; `modules/ruleset-default-branch/variables.tf` defaults to `"active"` and `org.tf` passes no override. The observation window is long over. Don't flip to `"evaluate"` except via the break-glass runbook.
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

# Run module tests (mock_provider, no API calls). Tests live under each
# module's tests/ dir and run with the module as root, so use -chdir per module.
# A bare `tofu test` from the repo root finds nothing (no root tests/ dir), and
# pointing -test-directory at a module from root crashes on the import blocks.
for m in org-baseline repo-baseline ruleset-default-branch ruleset-tag-protection; do
  tofu -chdir=modules/$m init -backend=false && tofu -chdir=modules/$m test
done
# Run a single module's tests
tofu -chdir=modules/org-baseline test

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
- **Squash is the only merge method, and that is load-bearing.** `repo-baseline` sets `allow_rebase_merge = false` because GitHub does not sign the commits it writes for a rebase-and-merge, and the default-branch ruleset's `required_signatures` then rejects them — a rebase merge wedges the PR. Don't re-enable it. `allow_auto_merge = true` grants the capability that Renovate's `platformAutomerge` needs (ADR-0007); it is still opt-in per PR, and GitHub refuses the request on a PR that is already mergeable, so a repo with no required check gets no automerge rather than an instant one.
- **Four org settings are unmanaged by the provider** (`members_can_delete_repositories`, `members_can_change_repo_visibility`, `members_can_invite_outside_collaborators`, `members_can_delete_issues`). They live in `scripts/set-extra-org-settings.sh` and must be set via the org's web UI; the script reads current state and flags drift.
- **Ruleset break-glass.** Org rulesets (default-branch, tag-protection) and the management-repo ruleset have no `bypass_actors` for the human owner. If a legitimate write must happen and a rule is the obstacle, follow `docs/runbooks/ruleset-break-glass.md` — two PRs (disable → work → re-enable), audit trail via pre/post rule-suites snapshot in a tracking issue. Not a routine merge bypass; cost is intentional.
- **Signing key rotation.** The release-tag SSH signing key (eventual home: AWS Secrets Manager `github-signing-key/release-tag`, once ADR-0002 impl #36 lands) rotates via a two-PR procedure (add new pubkey to `.github/allowed_signers` alongside old → promote `AWSCURRENT` → smoke-test release → remove old pubkey). Steady-state and emergency-compromise variants in `docs/runbooks/signing-key-rotation.md`. Audit trail: rotation PR descriptions must cite both outgoing and incoming SHA-256 fingerprints; tracking issue ties them together.

## GitHub Actions conventions

All `uses:` are pinned to a full commit SHA with a `# vX.Y.Z` comment. Every `actions/checkout` uses `persist-credentials: false`. Every job starts with `step-security/harden-runner` — `egress-policy: block` plus an explicit allowlist for credentialed jobs, `audit` for uncredentialed ones. New egress endpoints must be added to every credentialed workflow's allowlist (they are duplicated by design — see the allowlist blocks in `tofu-plan.yml`, `tofu-apply.yml`, `tofu-drift.yml`).

When bumping action versions, look up the current stable release; several have already been bumped beyond the design spec for security/compatibility reasons recorded in the Plan-1 completion notes.

## Governance + security policy

- **`CODEOWNERS`** assigns `*` to `@millsmillsymills`. Solo-owner posture; review-headcount-based gates (`require_code_owner_review`, `require_last_push_approval`) stay off in the default-branch ruleset for the same reason — re-enable only after a second maintainer joins.
- **`SECURITY.md`** routes vulnerability reports through GitHub Security Advisories on this repo, not public issues. 5-business-day initial response, 90-day coordinated disclosure.

## Agent skills

- **Issue tracker** — GitHub Issues at `millsymills-com/millsymills-com-org`. See `docs/agents/issue-tracker.md`.
- **Triage labels** — canonical five labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.
- **Domain docs** — single-context layout: `docs/adr/` (in use; holds ADR-0001, ADR-0002, ADR-0007) plus a `CONTEXT.md` at repo root if a future ADR introduces one. See `docs/agents/domain.md`.
