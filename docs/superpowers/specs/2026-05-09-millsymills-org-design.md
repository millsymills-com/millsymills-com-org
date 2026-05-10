---
title: millsymills-com GitHub org governance & portfolio design
date: 2026-05-09
status: draft — pending final user review
audience: Andrew Mills (millsmillsymills) — solo owner of millsymills-com org
---

# millsymills-com governance + portfolio: design spec

## Goal

Stand up the `millsymills-com` GitHub organization as a high-credibility, high-security
portfolio surface targeting three audiences simultaneously:

1. Recruiters / hiring managers at security-product companies (Snyk, Wiz, Crowdstrike, Datadog, Chainguard, Semgrep, etc.)
2. Enterprise CISOs and security leadership
3. Consulting / freelance clients

Personality must come through (reference: `p41m0n.com`).

## Constraints

- **Tier:** Personal Pro + Org Free (defer Team upgrade — design works on Free).
- **Sensitivity:** Current employer is Trail of Bits — never named in public artifacts.
  Avoid building anything that competes with their commercial offerings (smart-contract
  security, fuzzing/program-analysis tooling, binary analysis). Generalize all examples.
- **No moonlighting risk:** Stick to clearly-personal-time evidence. No competing tools.
- **Domains in scope:** GRC/governance, DevSecOps/supply-chain, AppSec/threat-modeling/detection-eng, Cloud/infra/identity.
- **Solo owner:** No external reviewers; chain-of-trust must hold without org-rulesets-on-private features.

## Approach (selected)

**Approach A — OpenTofu + S3 state + GitHub App + OIDC.**

- OpenTofu over Terraform: signals supply-chain literacy (FOSS fork after BSL change).
- S3 state with native S3 locking (Tofu 1.10+), KMS-encrypted, versioned.
- Two GitHub Apps as the only automated identities: `millsymills-org-bot-writer` (org-mutating, used by apply/drift) and `millsymills-org-bot-reader` (read-only, used by PR plan).
- AWS access from GHA via OIDC — zero static credentials in the repo.
- Self-managing repo: `millsymills-com-org` manages its own branch protection, required
  checks, and rulesets via the same Tofu pipeline.

Alternatives considered and rejected:
- Approach B (Terraform Cloud free tier) — simpler, loses OIDC narrative.
- Approach C (Pulumi TypeScript) — better testability, less universally legible to CISOs.

---

## Section 1 — Architecture overview *(approved)*

```
┌─────────────────────────────────────────────────────────────────────┐
│  millsymills-com-org  (this repo, public)                           │
│  • OpenTofu config that declares everything below                   │
│  • CI: PR → tofu plan (reader App); merge → tofu apply (writer App) │
│         nightly drift check (writer App)                            │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ apply/drift via writer App
                               │ plan via reader App
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  GitHub Org "millsymills-com"                                       │
│  ├── Org settings  (2FA required, default perm = none, GHAS on)     │
│  ├── Org-wide rulesets  (signed commits, required PR review, etc.)  │
│  ├── .github  repo   ← org-profile README, SECURITY.md, default WF  │
│  ├── millsymills-com-org  ← THIS repo (self-managing)               │
│  └── 3-5 portfolio repos  ← substantive work in your domains        │
└─────────────────────────────────────────────────────────────────────┘
                               ▲
                               │ OIDC (no static keys)
                               │
┌─────────────────────────────────────────────────────────────────────┐
│  AWS account (shared with personal infra)                           │
│  ├── S3 bucket "tfstate-millsymills-com" (KMS-encrypted, versioned) │
│  ├── KMS key  alias/tfstate-millsymills                             │
│  ├── Secrets Manager:                                               │
│  │     github-app-key/millsymills-org-bot-writer                    │
│  │     github-app-key/millsymills-org-bot-reader                    │
│  └── IAM roles:                                                     │
│        gha-millsymills-org-tofu-plan   (PR, reads reader key)       │
│        gha-millsymills-org-tofu-apply  (main, reads writer key)     │
│        gha-millsymills-org-tofu-drift  (cron, reads writer key)     │
└─────────────────────────────────────────────────────────────────────┘
```

Four moving parts:
1. **This repo** — single source of truth for org configuration.
2. **Two GitHub Apps** — `millsymills-org-bot-writer` (org-mutating, used only for apply + drift) and `millsymills-org-bot-reader` (read-only, used only for PR plan). Splitting the org-mutating identity from the PR plan path defends against fork-PR token-theft.
3. **AWS** — Tofu state (S3+KMS), App private keys (Secrets Manager), three IAM roles trusted via OIDC pinned to deployment environments.
4. **The org's other repos** — `.github` plus 2-3 portfolio repos. Configuration declared
   in this repo; content lives in the repos themselves.

**Self-managing property:** the Tofu config that manages `millsymills-com-org` lives in
`millsymills-com-org`. Branch protection, required checks, rulesets all flow through the
same PR-plan-apply pipeline. Drift gets caught nightly.

---

## Section 2 — Security baseline catalog *(approved)*

### Org-wide settings
- `two_factor_requirement_enabled = true`
- `default_repository_permission = "none"`
- `members_can_create_repositories = false` (and `_public`, `_private`, `_internal`)
- `members_can_delete_repositories = false`
- `members_can_change_repo_visibility = false`
- `members_can_invite_outside_collaborators = false`
- `members_can_delete_issues = false`
- `members_can_fork_private_repositories = false`
- `web_commit_signoff_required = true`
- `dependabot_alerts_enabled_for_new_repositories = true`
- `dependabot_security_updates_enabled_for_new_repositories = true`
- `dependency_graph_enabled_for_new_repositories = true`
- `secret_scanning_enabled_for_new_repositories = true`
- `secret_scanning_push_protection_enabled_for_new_repositories = true`
- `secret_scanning_validity_checks_enabled = true`
- `advanced_security_enabled_for_new_repositories = true` (free on public)

### Org-wide Actions policy
- **Allowlist:** `actions/*`, `github/*`, verified marketplace,
  curated 3rd party (`aquasecurity/trivy-action`, `sigstore/cosign-installer`,
  `step-security/harden-runner`, `actions/attest-*`, `dflook/terraform-*`).
- **Workflow permissions:** read-only `GITHUB_TOKEN` by default; explicit `permissions:`
  blocks per workflow.
- **Allow Actions to create/approve PRs:** false.
- **Forking:** internal & private forks disallowed.

### Org-wide rulesets
- **`default-branch-protection`** on `main`: PR required, status checks required,
  linear history required, signed commits required, force-push blocked, deletions
  restricted, up-to-date before merge.
- **`tag-protection`** on `v*`: forbid mutation/deletion.
- **`secret-pattern-push-rules`**: regex push-blocks layered on top of GitHub's Secret-Scanning Push Protection.

### Per-repo settings (`repo-baseline` module)
- Default branch `main`, `delete_branch_on_merge = true`
- `allow_squash_merge = true`, `allow_merge_commit = false`, `allow_rebase_merge = true`
- `vulnerability_alerts = true`, web commit signoff
- `has_wiki = false`, `has_projects = false`, `has_issues = true`
- Private vulnerability reporting enabled

### Per-repo files (templated by Tofu)
- `SECURITY.md` (private reporting + 90-day timeline)
- `CODEOWNERS` (you own everything)
- `.github/dependabot.yml` (daily for `github-actions`, weekly for ecosystems, grouped, 7-day cooldown)
- `.github/workflows/codeql.yml`
- `.github/workflows/zizmor.yml`
- `.github/workflows/scorecard.yml`
- `.github/workflows/sbom.yml` (CycloneDX + `actions/attest-sbom` on release)
- All actions SHA-pinned, enforced by zizmor.

### Personal account (`millsmillsymills`)
- 2FA via hardware security key (FIDO2)
- SSH commit signing, vigilant mode on
- Profile README links to org + pinned portfolio repos
- Audit existing 4 public repos for stale content

### Visible signals
- OpenSSF Scorecard badge per portfolio repo
- "Signed commits" badge
- "Security policy" link from each README
- Org profile README has a **"Security baseline"** section linking to this repo

### Out of scope
- SAML SSO, SCIM, audit log streaming, IP allow lists, custom roles, GHAS on private repos (Enterprise-only).
- Trail of Bits references.

### Decisions taken in this section
- **Org tier:** stay on Free. Design works on Free since portfolio repos will be public.
- **Commit signing:** SSH-key signing.

---

## Section 3 — Repo structure & content plan *(approved)*

### Layout inside `millsymills-com-org`

```
millsymills-com-org/
├── README.md                       — explains the whole architecture
├── ARCHITECTURE.md                 — diagrams + rationale
├── SECURITY.md                     — private reporting + responsible disclosure
├── CODEOWNERS
├── .github/
│   ├── workflows/
│   │   ├── tofu-plan.yml
│   │   ├── tofu-apply.yml
│   │   ├── tofu-drift.yml
│   │   ├── codeql.yml
│   │   ├── scorecard.yml
│   │   └── zizmor.yml
│   └── dependabot.yml
├── docs/
│   ├── controls/
│   ├── runbooks/
│   ├── adr/
│   └── superpowers/specs/          — design docs
├── modules/
│   ├── org-baseline/
│   ├── repo-baseline/
│   ├── ruleset-default-branch/
│   ├── ruleset-tag-protection/
│   └── team/
├── repos/
│   ├── _meta.tf                    — this repo + .github
│   ├── controls-as-code.tf
│   ├── terraform-aws-baseline.tf
│   └── incident-response-runbooks.tf
├── bootstrap/                      — one-time setup, self-disabling
│   ├── aws-bootstrap.sh
│   ├── github-bootstrap.md
│   ├── aws-output.json             — committed; ARNs/IDs only, no secrets
│   ├── github-output.json          — committed; App IDs only, no secrets
│   └── .disabled                   — sentinel after first successful run
├── org.tf                          — root org settings
├── providers.tf
├── variables.tf
├── versions.tf
└── .tflint.hcl, .pre-commit-config.yaml, .gitleaks.toml
```

### MVP repos in the org

| Repo | Audience | Domains | Sketch |
|---|---|---|---|
| `millsymills-com-org` | All | Meta / DevSecOps | The org-as-code; self-managing |
| `.github` | All | Meta | Org profile README, org SECURITY.md, default workflow templates |
| `controls-as-code` | CISOs, consulting | GRC | NIST CSF / SOC2 / ISO 27001 / CIS cross-mapped in YAML; static-site to GH Pages |
| `terraform-aws-baseline` | Recruiters, consulting | DevSecOps + Cloud | Tofu module: CloudTrail, GuardDuty, Security Hub, Config, IAM Identity Center, Access Analyzer, S3 public-block, CIS conformance |
| `incident-response-runbooks` | CISOs, consulting | IR / Detection | Library of generic IR playbooks + tabletop templates; no real incidents |

### Held back from MVP
- `mac-mdm-baselines` (Jamf/Entra) — distinctive, content-heavy. v2.
- `security-awareness-trainings` — corporate-friendly. v2.
- `gha-security-templates` — absorbed into `.github` defaults.
- `threat-models` — defer; ToB-adjacent territory.
- `detection-rules` — heavy authoring lift; defer.

### Pinned items
- **Org page:** `millsymills-com-org`, `controls-as-code`, `terraform-aws-baseline`, `incident-response-runbooks`.
- **Personal page:** pin same 4 from org via "pin from any repo"; profile README links to org and `millsymills.com`.

---

## Section 4 — CI/CD pipeline *(approved)*

### `tofu-plan.yml` (PR to `main`)

```
permissions: { id-token: write, pull-requests: write, contents: read }
environment: tofu-plan          # makes OIDC token's environment claim explicit
1. step-security/harden-runner@<sha>  audit egress
2. actions/checkout@<sha>             fetch-depth: 0
3. opentofu/setup-opentofu@<sha>      pinned version
4. aws-actions/configure-aws-credentials@<sha>   OIDC → role gha-…-tofu-plan
5. tofu init                          backend: s3 (native S3 locking)
6. tofu fmt -check
7. tofu validate
8. tflint
9. zizmor on .github/workflows
10. fetch READER App private key from Secrets Manager → mint installation token
11. tofu plan -no-color -out=tfplan
12. dflook/terraform-plan-comment    sticky PR comment
13. upload plan artifact (audit only, not used for apply)
```

### `tofu-apply.yml` (push to `main`)

```
permissions: { id-token: write, contents: read }
environment: tofu-apply         # required-reviewer protection optional, recommended
Same hardening + setup, OIDC → role gha-…-tofu-apply
tofu init
fetch WRITER App private key from Secrets Manager → mint installation token
tofu plan -out=tfplan && tofu apply tfplan
```

Re-plans on `main` rather than reusing the PR plan — guards against mid-air collisions.

### `tofu-drift.yml` (nightly + manual)

```
schedule: '0 7 * * *'   # 07:00 UTC
environment: tofu-drift
OIDC → role gha-…-tofu-drift
fetch WRITER App private key (drift may need to read org state and open issues)
tofu plan -detailed-exitcode
exit 0  → silent success (green badge)
exit 2  → open or update issue labeled `drift` with the diff (via writer App)
exit 1  → open issue labeled `drift-error` (via writer App)
```

### Branch protection on this repo (managed by itself)
- Require PR, require linear history, require signed commits.
- Required checks: `tofu plan`, `tofu validate`, `tflint`, `zizmor`, `gitleaks`, `actionlint`, `scorecard`.
- Restrict deletions, block force-push.
- Solo-dev caveat: GitHub Free can't require external reviewers. Chain-of-trust holds via:
  (a) `apply` only on `main`, only via OIDC, role trust pinned to this exact repo;
  (b) signed commits;
  (c) required status checks.
  Deployment environments wired up so a manual approval / wait gate can be added later.

### Secret/key rotation
- **GitHub App private keys (writer + reader):** rotate every 90 days, staggered (writer day 0, reader day 45). Runbook in `docs/runbooks/`. Tracked by recurring issue.
- **AWS access keys:** none — OIDC only.
- **KMS:** annual auto-rotation.
- **S3:** versioned, public-block, KMS-encrypted, no MFA-delete (overhead > benefit for solo).

### Bootstrap (chicken-and-egg)

See Section 6 for the full phase-by-phase walkthrough. Summary:
1. `bootstrap/aws-bootstrap.sh` — one-time local run with admin AWS creds. Creates S3 state bucket, KMS key, OIDC provider, three IAM roles, two Secrets Manager secret placeholders.
2. `bootstrap/github-bootstrap.md` — manual creation of two GitHub Apps (writer + reader); private keys uploaded to Secrets Manager.

After bootstrap, files are checked in with actual ARNs/IDs and the script self-disables. The directory becomes a historical artifact (itself a portfolio piece).

### Continuous-security CI (every repo, via `.github` defaults)
- CodeQL (per language)
- OpenSSF Scorecard (weekly + on push)
- zizmor (Actions audit)
- gitleaks (pre-commit + CI)
- actionlint (workflow lint)
- Dependency Review (PR-time dep diff)
- SBOM on release (`actions/attest-sbom` + CycloneDX)

---

## Section 5 — Auth & secret model *(approved)*

### Identities

| Identity | Lives where | Purpose |
|---|---|---|
| `millsmillsymills` | GitHub | Author commits; only human with org admin |
| `millsymills-org-bot-writer` (App) | GitHub | Org-mutating identity; used only by `apply` and `drift` |
| `millsymills-org-bot-reader` (App) | GitHub | Read-only org introspection; used only by `plan` |
| `gha-millsymills-org-tofu-plan` (IAM role) | AWS | Read state + **reader** App key, no writes |
| `gha-millsymills-org-tofu-apply` (IAM role) | AWS | Read state + **writer** App key, **write state** |
| `gha-millsymills-org-tofu-drift` (IAM role) | AWS | Read state + **writer** App key, no state writes; trusted via deployment environment |

Three defenses, layered:
1. **Two GitHub Apps.** The plan role only ever sees the **reader** App's private key. Reader has read-only permissions across the org. Even if the plan role's Secrets Manager access is compromised by a malicious fork PR, the worst outcome is read-only disclosure of org state — not org takeover.
2. **Two IAM roles.** Plan never has S3 write or KMS Encrypt — defends against a PR rewriting `tofu-plan.yml` to call `apply`.
3. **Fork-PR controls** (see "Fork PR threat" below).

### Trust chain (PR → merge → apply)

```
1. you commit, signed with SSH key, push to feature branch
2. open PR
3. GHA issues OIDC JWT with sub = "repo:.../millsymills-com-org:environment:tofu-plan"
   (sub uses the customized template; environment claim = "tofu-plan")
4. STS AssumeRoleWithWebIdentity → gha-…-tofu-plan (15-min creds)
5. Workflow:
     - reads state from S3 (KMS-decrypt) — read-only
     - reads READER App key from Secrets Manager (read-only org permissions)
     - mints reader-App installation token (1-hour, read-only)
     - tofu plan
     - posts plan as PR comment
6. self-review the plan, approve, merge
7. push to main triggers tofu-apply.yml
8. OIDC JWT with sub = "repo:.../millsymills-com-org:environment:tofu-apply"
   (customized template; environment claim = "tofu-apply")
9. STS → gha-…-tofu-apply (15-min creds)
10. workflow reads WRITER App key, mints writer-App token, re-plans, applies
11. new state to S3 (KMS-encrypt)
```

### IAM trust policy (apply role)

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:millsymills-com/millsymills-com-org:environment:tofu-apply",
      "token.actions.githubusercontent.com:repository_owner_id": "<numeric org id>",
      "token.actions.githubusercontent.com:repository_id": "<numeric repo id>",
      "token.actions.githubusercontent.com:environment": "tofu-apply"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:job_workflow_ref":
        "millsymills-com/millsymills-com-org/.github/workflows/tofu-apply.yml@refs/heads/main"
    }
  }
}
```

Pinning notes:
- Subject template is **customized at the GitHub side** (Org → Settings → Actions → OIDC) so `sub` includes the deployment environment. This makes `sub` matching robust without relying solely on `job_workflow_ref`.
- AWS IAM **does** evaluate any GitHub OIDC claim under the `token.actions.githubusercontent.com:` namespace as a condition key, including `job_workflow_ref`, `environment`, `repository_id`, `repository_owner_id`. This is documented and widely used in production.
- `repository_id` + `repository_owner_id` are immutable — they don't change if the repo is renamed or transferred, so an attacker can't squat on the name and assume the role.
- `environment: tofu-apply` ensures the token was issued from a job with `environment:` declared. Combined with required-reviewer protection on the environment, this becomes the manual-approval gate.

The plan role's trust policy is similar but uses `sub = "...:environment:tofu-plan"` and pins `head_ref` and `repository_id` to defend against fork PRs (see "Fork PR threat").

### IAM permission policies (sketch)

```
gha-…-tofu-plan       Allow: s3:Get*/List* on tfstate-millsymills/*
                            kms:Decrypt on the state KMS key
                            secretsmanager:GetSecretValue on github-app-key/READER ONLY
gha-…-tofu-apply      Allow: s3:Get*/List*/Put*/Delete* on tfstate-millsymills/*
                            kms:Decrypt, Encrypt, GenerateDataKey on the state KMS key
                            secretsmanager:GetSecretValue on github-app-key/WRITER
gha-…-tofu-drift      Allow: s3:Get*/List* on tfstate-millsymills/*
                            kms:Decrypt on the state KMS key
                            secretsmanager:GetSecretValue on github-app-key/WRITER (drift may need to open issues)
```

### KMS key policy
- Admin: account root + your IAM user (break-glass)
- Encrypt/Decrypt: apply role
- Decrypt only: plan + drift roles
- Annual rotation: automatic
- Deletion window: 30 days

### S3 bucket
- Versioned, KMS-encrypted, public access fully blocked, TLS-only.
- Lifecycle: expire non-current versions after 90 days.
- Bucket policy denies non-TLS and any request not encrypted with the specific KMS key.

### GitHub App permissions (least-privilege)

**`millsymills-org-bot-writer` (used only by apply + drift):**
- Repository: Administration RW, Contents RW, Metadata R, Pull-requests RW, Workflows RW, Issues RW, Pages RW, Variables RW, Secrets RW, Environments RW, Custom properties RW.
- Organization: Administration RW, Members RW, Secrets RW, Variables RW, Plan R, PAT policy RW.
- Subscribe to events: none.
- Where installable: only this org.

**`millsymills-org-bot-reader` (used only by plan, on PRs):**
- Repository: Administration **R**, Contents R, Metadata R, Pull-requests **W** (to post plan comments), Workflows R, Issues R, Pages R, Variables R, Secrets R, Environments R, Custom properties R.
- Organization: Administration **R**, Members R, Secrets R, Variables R, Plan R, PAT policy **R**.
- Subscribe to events: none.
- Where installable: only this org.

**App private keys:** each stored separately in AWS Secrets Manager (`github-app-key/millsymills-org-bot-{reader,writer}`), encrypted by the same KMS key, rotated every 90 days on a staggered schedule (writer on day 0, reader on day 45), never written to disk in CI.

### Fork PR threat (the P1 from review)

If `millsymills-com-org` is public, anyone can open a fork PR. By default GitHub Actions:
- Does **not** expose secrets to fork-PR workflows (good).
- **Does** issue OIDC tokens to fork-PR workflows. Token's `sub = repo:millsymills-com/millsymills-com-org:pull_request` — *identical to internal PRs*.
- Requires manual approval to run any workflow on a fork PR from a first-time contributor (default for public repos), but allows auto-run for subsequent PRs from the same contributor.

Layered defenses against a hostile fork PR:
1. **Repo setting:** Settings → Actions → "Require approval for all outside collaborators" (not just first-timers). Forces manual approval before any workflow runs from a fork.
2. **Customized OIDC subject:** at the org level, set the `sub` template to include `environment` and `head_ref`. This makes fork-PR `sub` distinguishable from internal-PR `sub`.
3. **Trust policy pin:** the plan role trust requires `repository_id = <numeric>` (immutable, can't be spoofed) AND `repository_owner_id = <numeric>` AND `environment = tofu-plan` (only set if the workflow declares the environment, which the plan workflow does explicitly).
4. **Two-App split:** even if all three above failed, the plan role can only fetch the **reader** App key. Worst case: read-only org disclosure, not org takeover.
5. **`step-security/harden-runner` audit egress:** the workflow can only reach allowlisted hosts (GitHub API, AWS API), so exfiltration to attacker-controlled servers is blocked.

### Honest threat-model gaps
1. **Compromise of personal GitHub account** — only owner. Mitigations: hardware key 2FA, vigilant mode, recovery codes in hardware safe, monthly session audit.
2. **Compromise of App installation token during a CI run** — `step-security/harden-runner` audits/blocks egress; SHA-pinned actions; no third-party secret-handling actions.
3. **Drift via the GitHub UI** — nightly drift detection opens an issue.
4. **AWS account compromise** — SCPs (defined in `terraform-aws-baseline`), CloudTrail, GuardDuty, MFA on root, IAM Identity Center for human access.
5. **Fork PR exploiting plan role** — addressed by the layered defenses in "Fork PR threat" above; residual risk is read-only org disclosure.
6. **Reader-App permission creep** — the reader App is a standing identity with org read access. If GitHub later allows reader to mint installation tokens with elevated scopes, this becomes a risk. Mitigation: 90-day key rotation, monthly App permission audit (runbook).

### Personal account hardening
- 2FA: hardware security key (FIDO2) + recovery codes in hardware safe.
- SSH commit signing, vigilant mode on.
- Monthly session review (manual; documented).
- Secondary email verified.
- Signed `keys.txt` repo on personal account publishing canonical SSH/GPG keys.
- Personal access tokens: none. API access goes through the GitHub App.

---

## Section 6 — Bootstrap path *(approved)*

The chicken-and-egg: nothing in this design works until S3, KMS, the IAM roles, and the
GitHub App all exist. Order of operations from "empty directory" to "CI-driven org-as-code".

### Phase 0 — prerequisites (manual, one-time)
- AWS account exists; local CLI configured with **admin** creds *for bootstrap only*.
- `gh` CLI logged in as `millsmillsymills` with `admin:org` scope (current token is
  `read:org` — needs upgrade for the import step).
- `tofu` installed locally, pinned in `versions.tf`.
- SSH commit signing wired up; verified by a signed test commit.

### Phase 1 — AWS bootstrap (`bootstrap/aws-bootstrap.sh`)
Idempotent shell script (or small Tofu config with **local** state in `bootstrap/`) that creates:
- S3 bucket `tfstate-millsymills-com` — versioned, public-block, KMS-SSE, TLS-only bucket policy, deny non-KMS-encrypted writes.
- KMS key `alias/tfstate-millsymills` — annual rotation, 30-day deletion window.
- IAM OIDC provider for `token.actions.githubusercontent.com`.
- IAM roles `gha-…-tofu-{plan,apply,drift}` with the trust + permission policies from Section 5.
- Two Secrets Manager secrets — `github-app-key/millsymills-org-bot-writer` and `github-app-key/millsymills-org-bot-reader` — empty placeholders, populated in Phase 2.
- Outputs ARNs/IDs to `bootstrap/aws-output.json` (committed; not secret).

### Phase 2 — GitHub App creation (`bootstrap/github-bootstrap.md`)
Manual UI walkthrough; not fully automatable. **Create two Apps** (writer + reader).
For each App:
1. Org → Settings → Developer settings → GitHub Apps → New GitHub App.
2. Name: `millsymills-org-bot-writer` (first run) / `millsymills-org-bot-reader` (second run); Homepage: link to this repo.
3. Webhook: **disabled** (Tofu pulls; no events needed).
4. Permissions: copy verbatim from the matching subsection of Section 5.
5. Where can be installed: only this org.
6. Generate private key, download `.pem`.
7. Install the App on `millsymills-com` with access to all repos.
8. Record App ID + Installation ID.
9. Upload key: `aws secretsmanager put-secret-value --secret-id github-app-key/<app-name> --secret-string file://*.pem`.
10. **Shred** the local `.pem` (`gshred -uz` or `srm`).
11. Commit each App's ID + Installation ID to `bootstrap/github-output.json` (public identifiers, not secrets).

Also: Org → Settings → Actions → set the OIDC subject template to include `environment` and `head_ref` (`repo:OWNER/REPO:environment:ENV` etc.) so trust policies can pin to environments. Document the chosen template in `bootstrap/github-output.json`.

### Phase 3 — initial Tofu apply (local, one-time)
1. Local env: `GH_APP_ID`, `GH_APP_INSTALLATION_ID`, decrypted private key (in-memory only).
2. `tofu init` — S3 backend now usable.
3. `tofu import` for the 5 existing GitHub objects (org, the 4 existing repos, the 1 private repo).
4. `tofu plan` — should show settings changes + new files in repos + new repo creations.
5. `tofu apply` — first real apply; commits the world.

### Phase 4 — hand off to CI
1. Manually trigger `tofu-drift.yml` from the GitHub UI; verify OIDC works end-to-end and drift = 0.
2. Push a no-op PR; verify `tofu-plan.yml` posts a clean plan comment.
3. Merge a real change; verify `tofu-apply.yml` runs and the change lands.
4. Reduce local AWS creds to read-only or revoke entirely.
5. From this moment forward: no manual `tofu apply` ever, anywhere. Drift detection enforces.

### Phase 5 — self-disable
1. `bootstrap/aws-bootstrap.sh` checks for `bootstrap/.disabled` and exits non-zero.
2. Final bootstrap commit writes `bootstrap/.disabled` with completion date + git SHA.
3. Re-running requires `--force` and a runbook entry explaining why.

### Phase 6 — adding new portfolio repos (steady state)
1. Create `repos/<name>.tf` declaring the repo + its config.
2. Open PR — Tofu plan posted.
3. Merge → apply creates the repo with full security baseline + scaffolding files.
4. Clone, populate content, push (signed commits, normal flow).

### Verification gates per phase

| Phase | Verification |
|---|---|
| 1 | `aws sts get-caller-identity`; `aws s3 ls tfstate-millsymills-com`; `aws iam get-role …` |
| 2 | `curl -H "Authorization: Bearer $JWT" https://api.github.com/app` returns the App |
| 3 | `tofu show` matches expectations; `tofu plan` is empty after apply |
| 4 | Drift workflow green via OIDC; PR plan comment posts |
| 5 | `bootstrap/.disabled` exists; rerun fails fast |

### Risks during bootstrap

| Risk | Mitigation |
|---|---|
| Local admin AWS creds leaked | Lock IAM user; rotate; CloudTrail blast-radius assessment |
| GH App private key leaked before Secrets Manager upload | Revoke in App settings; regenerate; new key never touches disk |
| OIDC misconfigured (most common bootstrap failure) | Manual `tofu-drift` dispatch as canary before declaring done |
| Tofu state corruption | S3 versioning + documented restore runbook |

### Import vs greenfield
The org already has 4 public + 1 private repo. We **import** them into Tofu rather than
delete-and-recreate. The first `tofu plan` after import will show diffs (current settings
≠ baseline); each diff is a deliberate, reviewable change.

---

## Section 7 — Portfolio narrative & personality *(approved)*

### Voice rules (apply to every README in the org)
- Terse first paragraph, no preamble. State what the thing is and what it does, in one sentence.
- Receipts only. Every claim links to code, a control reference (NIST/SOC2/CIS), or a demonstrable artifact. No "improvements", "robust", "comprehensive".
- Dry humor allowed; performative edginess forbidden.
- No "I'm passionate about". No "in my journey". No emoji unless functional.
- Retro / Y2K visual cues used **sparingly** — mostly in the org-profile README and pinned-repo social cards. Deep technical READMEs stay clean and monochrome.

### `.github` repo: org profile README (the front door)

```
# millsymills-com

Corporate security engineering, made visible.

This org is the public surface of Andrew Mills' security work — generalized,
reproducible, no employer references. Everything you see is managed as code,
audited nightly, signed end-to-end. Pick a thread:

| Thread | Repo |
|---|---|
| Govern the org itself, as code | millsymills-com-org |
| Map controls to NIST CSF / SOC2 / ISO 27001 / CIS | controls-as-code |
| Bootstrap a hardened AWS account in one apply | terraform-aws-baseline |
| IR playbooks and tabletop templates that actually run | incident-response-runbooks |

## Security baseline

Every repo here ships:
- Branch protection + signed commits + linear history (org ruleset)
- CodeQL, OpenSSF Scorecard, zizmor, gitleaks
- Dependabot with grouped updates and 7-day cooldown
- SBOM + SLSA-3 provenance attestation on each release
- Pinned action SHAs, audited egress (step-security/harden-runner)

Drift detection runs nightly. The org configuration lives in `millsymills-com-org`
and is enforced by GitHub Actions via OIDC — no static credentials, anywhere.

## What you won't find here

- A "hire me" button. The site is at millsymills.com.
- LinkedIn keywords.
- Anything that names current or recent employers.
- Real incidents. The IR templates are exercises, not artifacts.
```

### Personal profile README (`millsmillsymills/.github/profile/README.md`)

```
# andrew mills

corporate security engineer.

work lives at github.com/millsymills-com.
canonical site: millsymills.com.

— signed commits only.
— no PATs.
— if i didn't sign it, it's not me.
```

### Pinned repos (org page)
Order chosen for narrative flow: meta → governance → infra → ops.
1. `millsymills-com-org` — *"how this org governs itself"*
2. `controls-as-code` — *"how I think about controls"*
3. `terraform-aws-baseline` — *"how I'd start your AWS account"*
4. `incident-response-runbooks` — *"how I'd respond when it breaks"*

### Per-repo README skeleton (every portfolio repo)

```
# <repo-name>

<one-line "what this is and what it does">

## Why this exists
<3-5 sentences. State the operational problem and how this solves it.>

## What you get
- <bullet 1: a concrete artifact>
- <bullet 2: a concrete artifact>
- <bullet 3: a concrete artifact>

## How to use it
```sh
<copy-pasteable invocation>
```

## What it doesn't do
<2-4 honest limitations — earns trust>

## Controls implemented
<table mapping NIST CSF / SOC2 / ISO 27001 / CIS to specific files in the repo>

## Receipts
<links to: signed releases, scorecard badge, CodeQL results, SBOM, source>
```

### ADRs as portfolio content
Every non-obvious decision becomes an ADR in `docs/adr/`. Written for an external reader.
Discovered organically by anyone reading the repo. Examples:
- `0001-why-opentofu-not-terraform.md`
- `0002-two-iam-roles-for-plan-and-apply.md`
- `0003-github-app-not-pat.md`
- `0004-no-mfa-delete-on-state-bucket.md`
- `0005-no-team-tier-for-now.md`

A CISO reads three ADRs and knows the level. Free signal.

### Badges (per repo, top of README, in order)
- OpenSSF Scorecard — links to scorecard.dev results.
- License (Apache-2.0 unless otherwise needed).
- "signed" — links to a verification doc explaining how to verify signatures.
- No CI status badge. CI passes — that's the floor, not the flex.

### `millsymills.com` tie-in
- Org profile README links *to* `millsymills.com`; `millsymills.com` links *back to* the org and pinned repos.
- A short `/work` page on `millsymills.com` mirrors the four pinned repos with one-line descriptions and links.
- Org's `FUNDING.yml` either points to a donation/contact channel or omits a contact funnel entirely (user choice in Open Questions).
- Custom domain on the org's GitHub Pages later if `controls-as-code` ships a static site (e.g. `controls.millsymills.com`). Out of MVP.

### Social cards & avatar
- Org avatar: clean monochrome glyph (proposal: vaporwave-ish lock-and-key, or initials in Press Start 2P at high contrast). Avoid literal padlock emoji.
- Per-repo social-preview cards: generated PNG with the repo name in Press Start 2P, hot pink on deep navy, three corner badges (license, scorecard, signed).
- Cards generated by `.github/workflows/social-cards.yml` for consistency.

### Conspicuous absences (deliberate; mirrors p41m0n.com's restraint)
- No "About me" page anywhere on the org.
- No testimonial/endorsement section.
- No analytics on `millsymills-com.github.io`.
- No SEO keyword stuffing in repo descriptions.
- No "Sponsor" button on portfolio repos that aren't actually OSS tools (`terraform-aws-baseline` could; `millsymills-com-org` won't).
- No mention of Trail of Bits or any current/past employer, anywhere — including commit messages.

---

## Open questions / unresolved

- Do you have an AWS account already, and is it acceptable to use it for this org's state?
- Does `millsymills.com` have DNS in place; where is it pointed? GitHub Pages plans for the org (`millsymills-com.github.io`) in scope?
- Relationship between `millsymills.com` (your blog) and the org's web presence — same site, sub-section, or separate?
- `FUNDING.yml`: include a contact channel or omit?
- Should there be a `.github-private` repo for owner-only org-level templates (health files for private repos)? Out of MVP.

---

## Decisions ratified

| Decision | Choice | Rationale |
|---|---|---|
| Org tier | Free (defer Team) | Portfolio repos are public; org rulesets cover what we need |
| Personal tier | Pro | Already the case |
| IaC engine | OpenTofu | FOSS, supply-chain narrative, S3 native locking |
| State backend | AWS S3 + KMS | OIDC narrative; reuses personal AWS account |
| GitHub auth | Two Apps: `…-bot-writer` (apply/drift) + `…-bot-reader` (plan) | Replaces PATs; isolates org-mutating identity from PR plan path |
| AWS auth from CI | OIDC (no static keys) | Zero secrets in repo |
| Plan/apply roles | Two separate IAM roles, pinned to deployment environments | Defends against malicious-PR workflow rewrite + fork-PR token theft |
| OIDC subject template | Customized at org level to include environment + head_ref | Makes trust policies precise; fork-PR distinguishable from internal-PR |
| Commit signing | SSH-key signing | No new infra; vigilant mode |
| MVP repos | `millsymills-com-org`, `.github`, `controls-as-code`, `terraform-aws-baseline`, `incident-response-runbooks` | All three audiences, all four domains |
| Voice | Terse, receipts-driven, dry; mirrors p41m0n.com | Matches user's existing public voice |
| Employer references | Forbidden, including commit messages | Sensitivity constraint (Trail of Bits) |

---

## Review changelog

### 2026-05-09 — Codex review pass
- **P1 (substantive):** PR plan role no longer has access to org-mutating App key. Split GitHub App identity into `writer` (apply/drift) and `reader` (plan). Added explicit fork-PR threat model with five layered defenses. Pinned trust policies to deployment environments (`tofu-plan` / `tofu-apply`) and to immutable `repository_id`/`repository_owner_id`.
- **P2 (clarification):** Codex flagged `job_workflow_ref` as unsupported by AWS IAM. This is incorrect — AWS evaluates any GitHub OIDC claim under the issuer's namespace. Added a clarifying note in the trust-policy section. `job_workflow_ref` is retained as a defense-in-depth pin, but `sub` matching now carries the primary load via the customized subject template.
