# Plan 1 — Bootstrap + Baseline: completed

Completion date: 2026-05-12
Final commit before this note: `5d75c13`

## What's verified

- **AWS bootstrap resources** (S3, KMS, IAM, Secrets Manager) created and
  locked. Three GHA OIDC roles (`gha-millsymills-org-tofu-{plan,apply,drift}`)
  exist with inline `base`/`extra` policies; only OIDC tokens from this repo's
  workflows on `main` can assume them.
- **Two GitHub Apps** created (`millsymills-org-bot-writer`, `…-reader`); private
  keys stored in Secrets Manager only, fetched into `${RUNNER_TEMP}` at mode
  `0600` during workflow runs.
- **Org-baseline applied**; org-wide settings conform to the spec
  (Task 27 Step 1 output: `default_repository_permission = none`, all
  `members_can_*` false, web commit signoff required, 2FA required, dependabot
  + secret scanning + push protection enabled for new repos).
- **repo-baseline applied** on all five existing repos (`unraid-mcp`,
  `millsymills-com-org`, `unifi-mcp`, `gandi-mcp`, `protonmail-mcp`). Task 27
  Step 3 verified: `has_wiki=false`, `delete_branch_on_merge=true`,
  `allow_merge_commit=false`, `allow_squash_merge=true`,
  `web_commit_signoff_required=true` on each.
- **CI works end-to-end**:
  - `tofu-plan` posts a PR comment with the plan output (validated on canary
    PR #2 + on every subsequent PR).
  - `tofu-apply` runs on merge to `main` (validated on canary push + on
    every merge through PRs #3, #5, #8).
  - `tofu-drift` runs nightly (07:00 UTC) and on workflow_dispatch; the most
    recent run succeeded with no drift.
- **Continuous-security workflows** (codeql, scorecard, zizmor, gitleaks,
  actionlint) report green on every PR.
- **Required-status-checks ruleset** active on the management repo's default
  branch. Required contexts: `gate`, `zizmor`, `gitleaks`, `actionlint`,
  `analyze (actions)`. A deliberately-broken PR (#4) was confirmed BLOCKED.
- **Local admin AWS creds revoked**: root account access keys deleted from
  the AWS account; IAM user `mills` retains only `ReadOnlyAccess`. The state
  bucket KMS key denies `kms:Decrypt` to `mills`, so `tofu state list` from
  the local machine returns AccessDenied — stronger than the plan envisioned
  (the plan only required `s3:PutBucketPolicy` to fail; KMS gating gives
  defense in depth on reads too).
- **Bootstrap script self-sealed**: `bootstrap/.disabled` records the
  completion commit + UTC timestamp + operator. Re-runs require `--force`.

## What is deliberately deferred (Plan-2 / followup)

- **Signed-tag enforcement** in the release workflow (Plan-2). The
  tag-protection ruleset blocks update/delete on `v*` tags but does not
  enforce signed tag *objects*; that gate moves into a release workflow that
  validates tag signatures before publishing.
- **`vulnerability_alerts` provider deprecation**: migrate every
  `github_repository` resource to the sibling
  `github_repository_vulnerability_alerts` resource. Currently a perpetual
  warning under provider `~> 6.4`; fix as a focused commit when convenient.
- **PR-modified gate bypass**: an internal PR can edit
  `.github/workflows/tofu-plan.yml` to short-circuit the `gate` job.
  IAM `job_workflow_ref` still prevents AWS credential theft, but the
  required check could be satisfied by a modified workflow. Solo-owner
  threat model accepts this; Plan-2 mitigation options are CODEOWNERS on
  `.github/workflows/` once non-solo, or a `workflow_run`-based gate
  workflow stored only on `main`.

## Deviations from plan-1 v5 (documented in repo)

- **`repository_owner_id` OIDC trust condition** silently rejects on this
  account's GitHub OIDC provider; trust policies use `sub` + `repository_id`
  instead. See "Known limitations" in this plan.
- **`tofu-plan` workflow OIDC trust** loosened to `tofu-plan.yml@*` because
  PR refs are `refs/pull/N/merge`, not `refs/heads/main`. Apply/drift roles
  stayed pinned to main.
- **GitHub App `mills…-reader`** raised from
  `organization_administration: read` to `:write` because GitHub silently
  demands `:write` on org-ruleset GETs despite docs claiming `:read` suffices.
- **`step-security/harden-runner`** bumped `v2.10.4 → v2.19.1` mid-Task-25
  because v2.10.4 has four GHSAs flagged by zizmor's online audits.
- **`gitleaks-action@v2.x`** replaced with a direct gitleaks binary install
  (`v8.21.2`, matching the pre-commit hook) — the action's v2.x requires a
  paid license for org-owned repos.
- **`raven-actions/actionlint@v2.0.0`** bumped to `v2.1.2` (v2.0.0 broken on
  Node 20 with `ERR_PACKAGE_PATH_NOT_EXPORTED`).
- **`github/codeql-action@v3.27.0`** bumped to `v3.35.4` (v3.27.0 did not
  yet recognize the `actions` analyzer language).
- **Workflow allowlists** expanded to include `sts.us-west-1.amazonaws.com`,
  `get.opentofu.org`, and `release-assets.githubusercontent.com` — needed
  once harden-runner v2.19.1 started enforcing `egress-policy: block`
  strictly (v2.10.4 frequently fell back to audit).
- **`tofu-plan` workflow lost its `paths:` filter** so the required `gate`
  check reports on every PR (doc-only PRs previously deadlocked the
  ruleset).

## Where to look next

- Plan 2: portfolio repos (`.github` org profile, `controls-as-code`,
  `terraform-aws-baseline`, `incident-response-runbooks`) and their content
  (READMEs, ADRs, runbooks). Voice/personality work informed by `p41m0n.com`.
- Both org rulesets are now in `enforcement = "active"` (flipped on
  2026-05-19 via PR #16, after a full week of evaluate-mode observation).
- The bootstrap script's lockdown is reversible only via `--force` and a
  new runbook entry; treat re-runs as a deliberate, auditable change.
