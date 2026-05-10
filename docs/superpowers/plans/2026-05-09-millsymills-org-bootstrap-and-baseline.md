# millsymills-com Bootstrap + Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `millsymills-com` GitHub organization as code: bootstrap AWS state + GitHub Apps, codify the security baseline in OpenTofu modules, import existing org/repos, and prove the PR-plan / merge-apply / nightly-drift CI loop works end-to-end via OIDC.

**Architecture:** Single management repo `millsymills-com-org` (this directory) holds OpenTofu config. Two GitHub Apps (writer + reader) are the only automated identities. AWS S3 + KMS hold Tofu state; three IAM roles (`tofu-{plan,apply,drift}`) are assumed via OIDC pinned to GitHub-Actions deployment environments. The repo manages its own branch protection + required checks via the same Tofu pipeline.

**Tech Stack:** OpenTofu ≥1.10 (S3 native locking), AWS (S3, KMS, IAM, Secrets Manager), `terraform-provider-github` v6.x via two GitHub Apps, GitHub Actions with OIDC, `bash` + `shellcheck` + `bats` for bootstrap script, `tflint`, `zizmor`, `gitleaks`, `actionlint`, `step-security/harden-runner`.

**Reference:** Spec at `docs/superpowers/specs/2026-05-09-millsymills-org-design.md`.

**Conventions used in this plan:**
- All commands run from repo root (`/Users/mills/Desktop/Projects/millsymills-com-org`) unless stated otherwise.
- `<acct>` = AWS account ID (recorded in `bootstrap/aws-output.json`).
- `<org-id>` and `<repo-id>` = numeric GitHub IDs (recorded in `bootstrap/github-output.json`).
- Every commit message uses imperative mood and is signed (SSH key signing already configured per spec).
- Every Tofu apply step requires the previous step's plan to have been reviewed before applying.

---

## Phase A — Bootstrap (one-time setup)

### Task 1: Repo skeleton and tooling

**Files:**
- Create: `.gitignore`
- Create: `.editorconfig`
- Create: `.tool-versions`
- Create: `.pre-commit-config.yaml`
- Create: `.gitleaks.toml`
- Create: `.tflint.hcl`
- Create: `README.md` (placeholder; full content in Plan 2)
- Create: `CODEOWNERS`
- Create: `SECURITY.md`

- [ ] **Step 1: Write `.gitignore`**

```
# Tofu
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
.terraform/
.terraform.lock.hcl.local
crash.log

# Secrets / local
*.pem
*.key
.env
.env.*
bootstrap/*.local.json

# OS / editor
.DS_Store
.idea/
.vscode/
*.swp

# Tofu plan artifacts
tfplan
*.tfplan
plan.out
```

- [ ] **Step 2: Write `.editorconfig`**

```
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.{md,markdown}]
trim_trailing_whitespace = false

[Makefile]
indent_style = tab
```

- [ ] **Step 3: Write `.tool-versions`**

```
opentofu 1.10.3
tflint 0.55.1
shellcheck 0.10.0
bats 1.11.1
```

- [ ] **Step 4: Write `.pre-commit-config.yaml`**

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: detect-private-key

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks

  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.10.0
    hooks:
      - id: shellcheck

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tflint

  - repo: https://github.com/rhysd/actionlint
    rev: v1.7.7
    hooks:
      - id: actionlint
```

- [ ] **Step 5: Write `.gitleaks.toml`**

```toml
[extend]
useDefault = true

[allowlist]
description = "Allowlist for project-local config"
paths = [
    '''docs/.*''',
    '''bootstrap/aws-output\.json''',
    '''bootstrap/github-output\.json''',
]
```

- [ ] **Step 6: Write `.tflint.hcl`**

```hcl
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "github" {
  enabled = true
  version = "0.1.0"
  source  = "github.com/terraform-linters/tflint-ruleset-github"
}

plugin "aws" {
  enabled = true
  version = "0.36.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  format = "compact"
  call_module_type = "all"
}
```

- [ ] **Step 7: Write `README.md` placeholder**

```markdown
# millsymills-com-org

Org-as-code for the `millsymills-com` GitHub organization.

Status: bootstrap in progress. Full README in Plan 2.

See `docs/superpowers/specs/2026-05-09-millsymills-org-design.md`.
```

- [ ] **Step 8: Write `CODEOWNERS`**

```
*   @millsmillsymills
```

- [ ] **Step 9: Write `SECURITY.md`**

```markdown
# Security policy

Report vulnerabilities privately via GitHub Security Advisories on this repo.
Initial response within 5 business days. Coordinated disclosure within 90 days.

Do not open public issues for security reports.
```

- [ ] **Step 10: Install pre-commit hooks**

Run: `pre-commit install`
Expected: `pre-commit installed at .git/hooks/pre-commit`

- [ ] **Step 11: Run pre-commit on all files (sanity check)**

Run: `pre-commit run --all-files`
Expected: all hooks pass (some files won't exist yet — fine; hooks should still pass on what exists).

- [ ] **Step 12: Commit**

```bash
git add .gitignore .editorconfig .tool-versions .pre-commit-config.yaml .gitleaks.toml .tflint.hcl README.md CODEOWNERS SECURITY.md
git commit -m "chore: project skeleton and pre-commit tooling"
```

---

### Task 2: Bootstrap directory and safety guard

**Files:**
- Create: `bootstrap/aws-bootstrap.sh`
- Create: `bootstrap/lib/_common.sh`
- Create: `bootstrap/tests/test_disabled_guard.bats`
- Create: `bootstrap/README.md`

- [ ] **Step 1: Write the failing bats test for the disabled-guard**

```bash
# bootstrap/tests/test_disabled_guard.bats
#!/usr/bin/env bats

setup() {
  export BOOTSTRAP_DIR="$(mktemp -d)"
  cp "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" "${BOOTSTRAP_DIR}/aws-bootstrap.sh"
  cp -r "${BATS_TEST_DIRNAME}/../lib" "${BOOTSTRAP_DIR}/"
  chmod +x "${BOOTSTRAP_DIR}/aws-bootstrap.sh"
}

teardown() {
  rm -rf "${BOOTSTRAP_DIR}"
}

@test "aws-bootstrap.sh exits non-zero when .disabled exists and --force not passed" {
  touch "${BOOTSTRAP_DIR}/.disabled"
  run "${BOOTSTRAP_DIR}/aws-bootstrap.sh" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to run"* ]]
}

@test "aws-bootstrap.sh proceeds when .disabled exists and --force passed" {
  touch "${BOOTSTRAP_DIR}/.disabled"
  run "${BOOTSTRAP_DIR}/aws-bootstrap.sh" --dry-run --force
  [ "$status" -eq 0 ]
}

@test "aws-bootstrap.sh proceeds when .disabled does not exist" {
  run "${BOOTSTRAP_DIR}/aws-bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats bootstrap/tests/test_disabled_guard.bats`
Expected: FAIL — script does not exist yet.

- [ ] **Step 3: Write `bootstrap/lib/_common.sh`**

```bash
#!/usr/bin/env bash
# Common helpers for bootstrap scripts. Source from each script.
set -euo pipefail

log() { printf '[bootstrap] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

assert_aws_admin() {
  require_cmd aws
  aws sts get-caller-identity >/dev/null \
    || die "AWS credentials not configured (run \`aws configure\` first)"
}

confirm() {
  local prompt="$1"
  printf '%s [y/N]: ' "$prompt"
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] || die "aborted by user"
}
```

- [ ] **Step 4: Write `bootstrap/aws-bootstrap.sh` (skeleton with --disabled guard only)**

```bash
#!/usr/bin/env bash
# AWS bootstrap for the millsymills-com-org Tofu pipeline.
# Idempotent. Run once. Self-disables on success via bootstrap/.disabled sentinel.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/_common.sh
. "${SCRIPT_DIR}/lib/_common.sh"

DISABLED_SENTINEL="${SCRIPT_DIR}/.disabled"
FORCE=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--force]

  --dry-run   Print actions but make no changes.
  --force     Run even if bootstrap/.disabled is present.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ -f "${DISABLED_SENTINEL}" && "${FORCE}" -ne 1 ]]; then
  log "refusing to run: ${DISABLED_SENTINEL} exists. Pass --force to override."
  exit 1
fi

log "starting AWS bootstrap (dry-run=${DRY_RUN}, force=${FORCE})"

# Phase 1: TODO in subsequent tasks

log "bootstrap complete (skeleton only)"
```

- [ ] **Step 5: Make script executable**

Run: `chmod +x bootstrap/aws-bootstrap.sh`
Expected: no output.

- [ ] **Step 6: Run the bats test to verify it now passes**

Run: `bats bootstrap/tests/test_disabled_guard.bats`
Expected: 3 tests, 3 passed.

- [ ] **Step 7: Run shellcheck on the script**

Run: `shellcheck bootstrap/aws-bootstrap.sh bootstrap/lib/_common.sh`
Expected: no output (clean).

- [ ] **Step 8: Write `bootstrap/README.md`**

```markdown
# bootstrap

One-time setup for the millsymills-com-org Tofu pipeline.

## Order of operations

1. `./aws-bootstrap.sh` — creates AWS state infrastructure (S3, KMS, IAM, Secrets Manager).
2. Follow `github-bootstrap.md` to create the two GitHub Apps and customize OIDC subject template.
3. Run `tofu init` and `tofu import` (see top-level docs).
4. Verify CI works end-to-end.
5. Touch `bootstrap/.disabled` (or commit it as part of the final bootstrap commit) to lock further runs.

## Files

- `aws-bootstrap.sh` — idempotent AWS provisioning script.
- `lib/_common.sh` — shared helpers.
- `tests/` — bats tests.
- `aws-output.json` — committed; non-secret ARNs and IDs.
- `github-bootstrap.md` — manual GitHub App creation runbook.
- `github-output.json` — committed; non-secret App IDs and Installation IDs.
- `.disabled` — sentinel file; if present, scripts refuse to run unless `--force`.

## Forbidden after bootstrap

After `bootstrap/.disabled` is committed, no manual `tofu apply` from any developer machine.
All changes go through PR → CI plan → merge → CI apply.
```

- [ ] **Step 9: Commit**

```bash
git add bootstrap/
git commit -m "feat(bootstrap): scaffold aws-bootstrap.sh with disabled-guard"
```

---

### Task 3: Bootstrap script — S3 state bucket

**Files:**
- Modify: `bootstrap/aws-bootstrap.sh`
- Create: `bootstrap/tests/test_s3_creation.bats`

- [ ] **Step 1: Write the failing bats test for S3 bucket creation in dry-run**

```bash
# bootstrap/tests/test_s3_creation.bats
#!/usr/bin/env bats

setup() {
  export AWS_REGION="us-east-1"
  export STATE_BUCKET="tfstate-millsymills-com-test"
}

@test "dry-run prints S3 bucket creation plan with correct name" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would create S3 bucket"* ]]
  [[ "$output" == *"tfstate-millsymills-com"* ]]
}

@test "dry-run prints versioning, public-block, and KMS-SSE bucket policy" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"versioning"* ]]
  [[ "$output" == *"public access block"* ]]
  [[ "$output" == *"TLS-only"* ]]
}
```

- [ ] **Step 2: Run test to confirm it fails**

Run: `bats bootstrap/tests/test_s3_creation.bats`
Expected: FAIL — output doesn't include S3 messages.

- [ ] **Step 3: Add S3 bucket function to `aws-bootstrap.sh`**

Append this section *before* the final `log "bootstrap complete..."` line:

```bash
# ---------------------------------------------------------------------
# Phase 1.1: S3 state bucket
# ---------------------------------------------------------------------

STATE_BUCKET="${STATE_BUCKET:-tfstate-millsymills-com}"
AWS_REGION="${AWS_REGION:-us-east-1}"

create_state_bucket() {
  log "would create S3 bucket: ${STATE_BUCKET} (region ${AWS_REGION})"
  log "  - versioning: enabled"
  log "  - public access block: all four blocks on"
  log "  - TLS-only bucket policy"
  log "  - default SSE-KMS using state KMS key"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  assert_aws_admin

  if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>/dev/null; then
    log "S3 bucket ${STATE_BUCKET} already exists; skipping creation"
  else
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}"
    else
      aws s3api create-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}" \
        --create-bucket-configuration LocationConstraint="${AWS_REGION}"
    fi
    log "created S3 bucket ${STATE_BUCKET}"
  fi

  aws s3api put-bucket-versioning --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled

  aws s3api put-public-access-block --bucket "${STATE_BUCKET}" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  aws s3api put-bucket-lifecycle-configuration --bucket "${STATE_BUCKET}" \
    --lifecycle-configuration '{
      "Rules": [
        {
          "ID": "expire-noncurrent-versions",
          "Status": "Enabled",
          "Filter": {"Prefix": ""},
          "NoncurrentVersionExpiration": {"NoncurrentDays": 90}
        }
      ]
    }'

  # KMS-SSE default + bucket policy applied in Task 4 after KMS key exists.
}

create_state_bucket
```

- [ ] **Step 4: Run the bats test to verify it passes**

Run: `bats bootstrap/tests/test_s3_creation.bats`
Expected: 2 tests, 2 passed.

- [ ] **Step 5: Run shellcheck**

Run: `shellcheck bootstrap/aws-bootstrap.sh`
Expected: no output (clean).

- [ ] **Step 6: Commit**

```bash
git add bootstrap/
git commit -m "feat(bootstrap): add idempotent S3 state bucket creation"
```

---

### Task 4: Bootstrap script — KMS key + bucket SSE/policy

**Files:**
- Modify: `bootstrap/aws-bootstrap.sh`
- Create: `bootstrap/tests/test_kms_creation.bats`

- [ ] **Step 1: Write the failing bats test**

```bash
# bootstrap/tests/test_kms_creation.bats
#!/usr/bin/env bats

@test "dry-run mentions KMS key alias and rotation" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias/tfstate-millsymills"* ]]
  [[ "$output" == *"annual rotation"* ]]
}

@test "dry-run mentions bucket policy with TLS deny and KMS deny" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"deny non-TLS"* ]]
  [[ "$output" == *"deny non-KMS"* ]]
}
```

- [ ] **Step 2: Run test to confirm fail**

Run: `bats bootstrap/tests/test_kms_creation.bats`
Expected: FAIL.

- [ ] **Step 3: Append KMS function to `aws-bootstrap.sh` (between `create_state_bucket` body and the final log line)**

```bash
# ---------------------------------------------------------------------
# Phase 1.2: KMS key for state encryption
# ---------------------------------------------------------------------

KMS_ALIAS="${KMS_ALIAS:-alias/tfstate-millsymills}"

create_state_kms_key() {
  log "would create KMS key: ${KMS_ALIAS}"
  log "  - annual rotation: enabled"
  log "  - deletion window: 30 days"
  log "  - admin: account root + caller IAM identity (break-glass)"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  assert_aws_admin
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)

  EXISTING_KEY_ID=$(aws kms list-aliases \
    --query "Aliases[?AliasName=='${KMS_ALIAS}'].TargetKeyId | [0]" \
    --output text)

  if [[ -n "${EXISTING_KEY_ID}" && "${EXISTING_KEY_ID}" != "None" ]]; then
    log "KMS key ${KMS_ALIAS} already exists (id ${EXISTING_KEY_ID}); skipping create"
    KMS_KEY_ID="${EXISTING_KEY_ID}"
  else
    KEY_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RootAccountAccess",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::${ACCOUNT_ID}:root"},
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "BreakGlassAdmin",
      "Effect": "Allow",
      "Principal": {"AWS": "${CALLER_ARN}"},
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
EOF
)
    KMS_KEY_ID=$(aws kms create-key \
      --description "Tofu state encryption for millsymills-com-org" \
      --policy "${KEY_POLICY}" \
      --query KeyMetadata.KeyId --output text)
    aws kms create-alias --alias-name "${KMS_ALIAS}" --target-key-id "${KMS_KEY_ID}"
    aws kms enable-key-rotation --key-id "${KMS_KEY_ID}"
    log "created KMS key ${KMS_KEY_ID} aliased ${KMS_ALIAS}"
  fi

  KMS_KEY_ARN=$(aws kms describe-key --key-id "${KMS_KEY_ID}" --query KeyMetadata.Arn --output text)

  # Apply default SSE-KMS to the bucket
  aws s3api put-bucket-encryption --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration "{
      \"Rules\": [{
        \"ApplyServerSideEncryptionByDefault\": {
          \"SSEAlgorithm\": \"aws:kms\",
          \"KMSMasterKeyID\": \"${KMS_KEY_ARN}\"
        },
        \"BucketKeyEnabled\": true
      }]
    }"

  # Bucket policy: deny non-TLS, deny non-KMS-encrypted writes
  log "applying bucket policy: deny non-TLS, deny non-KMS"
  BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyNonTLS",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${STATE_BUCKET}",
        "arn:aws:s3:::${STATE_BUCKET}/*"
      ],
      "Condition": {"Bool": {"aws:SecureTransport": "false"}}
    },
    {
      "Sid": "DenyNonKMSEncryptedWrites",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${STATE_BUCKET}/*",
      "Condition": {
        "StringNotEquals": {"s3:x-amz-server-side-encryption": "aws:kms"}
      }
    },
    {
      "Sid": "DenyWrongKMSKey",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${STATE_BUCKET}/*",
      "Condition": {
        "StringNotEqualsIfExists": {
          "s3:x-amz-server-side-encryption-aws-kms-key-id": "${KMS_KEY_ARN}"
        }
      }
    }
  ]
}
EOF
)
  aws s3api put-bucket-policy --bucket "${STATE_BUCKET}" --policy "${BUCKET_POLICY}"
}

create_state_kms_key
```

- [ ] **Step 4: Run bats**

Run: `bats bootstrap/tests/test_kms_creation.bats`
Expected: 2 passed.

- [ ] **Step 5: Run shellcheck**

Run: `shellcheck bootstrap/aws-bootstrap.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add bootstrap/
git commit -m "feat(bootstrap): create KMS key with annual rotation and bucket policies"
```

---

### Task 5: Bootstrap script — IAM OIDC provider and three roles

**Files:**
- Modify: `bootstrap/aws-bootstrap.sh`
- Create: `bootstrap/tests/test_iam_creation.bats`

- [ ] **Step 1: Write the failing bats test**

```bash
# bootstrap/tests/test_iam_creation.bats
#!/usr/bin/env bats

@test "dry-run mentions OIDC provider for github actions" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"token.actions.githubusercontent.com"* ]]
}

@test "dry-run mentions all three IAM roles" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"gha-millsymills-org-tofu-plan"* ]]
  [[ "$output" == *"gha-millsymills-org-tofu-apply"* ]]
  [[ "$output" == *"gha-millsymills-org-tofu-drift"* ]]
}

@test "dry-run mentions environment-pinned trust policies" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"environment:tofu-plan"* ]]
  [[ "$output" == *"environment:tofu-apply"* ]]
  [[ "$output" == *"environment:tofu-drift"* ]]
}
```

- [ ] **Step 2: Run test to confirm fail**

Run: `bats bootstrap/tests/test_iam_creation.bats`
Expected: FAIL.

- [ ] **Step 3: Append IAM functions to `aws-bootstrap.sh`**

```bash
# ---------------------------------------------------------------------
# Phase 1.3: IAM OIDC provider + three roles
# ---------------------------------------------------------------------

GH_OIDC_URL="https://token.actions.githubusercontent.com"
ORG_REPO="millsymills-com/millsymills-com-org"

create_oidc_provider() {
  log "would create IAM OIDC provider for ${GH_OIDC_URL}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  EXISTING=$(aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn | [0]" \
    --output text)

  if [[ -n "${EXISTING}" && "${EXISTING}" != "None" ]]; then
    log "OIDC provider already exists: ${EXISTING}"
    OIDC_PROVIDER_ARN="${EXISTING}"
  else
    OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
      --url "${GH_OIDC_URL}" \
      --client-id-list "sts.amazonaws.com" \
      --thumbprint-list "ffffffffffffffffffffffffffffffffffffffff" \
      --query OpenIDConnectProviderArn --output text)
    log "created OIDC provider ${OIDC_PROVIDER_ARN}"
  fi
}

create_role() {
  local role_name="$1"
  local environment="$2"
  local extra_perms_json="$3"

  log "would create IAM role: ${role_name} (environment:${environment})"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  # Look up org and repo IDs (immutable claims for trust policy).
  ORG_ID=$(gh api /orgs/millsymills-com --jq .id)
  REPO_ID=$(gh api /repos/millsymills-com/millsymills-com-org --jq .id)
  WORKFLOW_REF="millsymills-com/millsymills-com-org/.github/workflows/tofu-${environment#tofu-}.yml@refs/heads/main"

  TRUST=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "${OIDC_PROVIDER_ARN}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:${ORG_REPO}:environment:${environment}",
        "token.actions.githubusercontent.com:environment": "${environment}",
        "token.actions.githubusercontent.com:repository_id": "${REPO_ID}",
        "token.actions.githubusercontent.com:repository_owner_id": "${ORG_ID}"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:job_workflow_ref": "${WORKFLOW_REF}"
      }
    }
  }]
}
EOF
)

  if aws iam get-role --role-name "${role_name}" >/dev/null 2>&1; then
    log "role ${role_name} exists; updating trust policy"
    aws iam update-assume-role-policy --role-name "${role_name}" --policy-document "${TRUST}"
  else
    aws iam create-role --role-name "${role_name}" \
      --assume-role-policy-document "${TRUST}" \
      --max-session-duration 3600 \
      --description "GitHub Actions OIDC role for ${environment} on ${ORG_REPO}"
  fi

  # Inline policy: state read; lock-file write (for plan/drift); KMS decrypt;
  # extra perms layered per role.
  BASE_PERMS=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StateRead",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${STATE_BUCKET}",
        "arn:aws:s3:::${STATE_BUCKET}/*"
      ]
    },
    {
      "Sid": "LockFileWriteScopedToTflock",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::${STATE_BUCKET}/*.tflock"
    },
    {
      "Sid": "KMSReadAndLockEncrypt",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"],
      "Resource": "${KMS_KEY_ARN}"
    }
  ]
}
EOF
)
  aws iam put-role-policy --role-name "${role_name}" --policy-name base \
    --policy-document "${BASE_PERMS}"

  if [[ -n "${extra_perms_json}" ]]; then
    aws iam put-role-policy --role-name "${role_name}" --policy-name extra \
      --policy-document "${extra_perms_json}"
  fi
}

create_oidc_provider

# Role-specific extras
PLAN_EXTRA=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:${AWS_REGION}:*:secret:github-app-key/millsymills-org-bot-reader-*"
  }]
}
EOF
)

APPLY_EXTRA=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StateWrite",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::${STATE_BUCKET}/*"
    },
    {
      "Sid": "KMSReEncrypt",
      "Effect": "Allow",
      "Action": ["kms:ReEncrypt*"],
      "Resource": "${KMS_KEY_ARN}"
    },
    {
      "Sid": "WriterAppKey",
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:*:secret:github-app-key/millsymills-org-bot-writer-*"
    }
  ]
}
EOF
)

DRIFT_EXTRA=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "arn:aws:secretsmanager:${AWS_REGION}:*:secret:github-app-key/millsymills-org-bot-writer-*"
  }]
}
EOF
)

create_role "gha-millsymills-org-tofu-plan"  "tofu-plan"  "${PLAN_EXTRA}"
create_role "gha-millsymills-org-tofu-apply" "tofu-apply" "${APPLY_EXTRA}"
create_role "gha-millsymills-org-tofu-drift" "tofu-drift" "${DRIFT_EXTRA}"
```

- [ ] **Step 4: Run bats**

Run: `bats bootstrap/tests/test_iam_creation.bats`
Expected: 3 passed.

- [ ] **Step 5: Run shellcheck**

Run: `shellcheck bootstrap/aws-bootstrap.sh`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add bootstrap/
git commit -m "feat(bootstrap): provision OIDC provider and three environment-pinned IAM roles"
```

---

### Task 6: Bootstrap script — Secrets Manager placeholders + output JSON

**Files:**
- Modify: `bootstrap/aws-bootstrap.sh`
- Create: `bootstrap/tests/test_secrets_and_output.bats`

- [ ] **Step 1: Write the failing test**

```bash
# bootstrap/tests/test_secrets_and_output.bats
#!/usr/bin/env bats

@test "dry-run mentions both Secrets Manager placeholders" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"github-app-key/millsymills-org-bot-writer"* ]]
  [[ "$output" == *"github-app-key/millsymills-org-bot-reader"* ]]
}

@test "dry-run mentions writing aws-output.json" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"aws-output.json"* ]]
}
```

- [ ] **Step 2: Run test to confirm fail**

Run: `bats bootstrap/tests/test_secrets_and_output.bats`
Expected: FAIL.

- [ ] **Step 3: Append Secrets Manager + output to `aws-bootstrap.sh`**

```bash
# ---------------------------------------------------------------------
# Phase 1.4: Secrets Manager placeholders for GitHub App keys
# ---------------------------------------------------------------------

create_app_key_secret() {
  local secret_name="$1"
  log "would create Secrets Manager secret: ${secret_name} (placeholder)"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  if aws secretsmanager describe-secret --secret-id "${secret_name}" >/dev/null 2>&1; then
    log "secret ${secret_name} already exists; skipping create"
    return 0
  fi

  aws secretsmanager create-secret \
    --name "${secret_name}" \
    --description "GitHub App private key (PEM); populate manually after App creation" \
    --kms-key-id "${KMS_KEY_ARN}" \
    --secret-string '{"placeholder": "populate after GitHub App creation"}' \
    >/dev/null
}

create_app_key_secret "github-app-key/millsymills-org-bot-writer"
create_app_key_secret "github-app-key/millsymills-org-bot-reader"

# ---------------------------------------------------------------------
# Phase 1.5: Write aws-output.json (committed; non-secret)
# ---------------------------------------------------------------------

write_output_json() {
  local output_file="${SCRIPT_DIR}/aws-output.json"
  log "would write aws-output.json to ${output_file}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi

  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

  cat > "${output_file}" <<EOF
{
  "account_id": "${ACCOUNT_ID}",
  "region": "${AWS_REGION}",
  "state_bucket": "${STATE_BUCKET}",
  "kms_key_alias": "${KMS_ALIAS}",
  "kms_key_arn": "${KMS_KEY_ARN}",
  "oidc_provider_arn": "${OIDC_PROVIDER_ARN}",
  "roles": {
    "plan":  "arn:aws:iam::${ACCOUNT_ID}:role/gha-millsymills-org-tofu-plan",
    "apply": "arn:aws:iam::${ACCOUNT_ID}:role/gha-millsymills-org-tofu-apply",
    "drift": "arn:aws:iam::${ACCOUNT_ID}:role/gha-millsymills-org-tofu-drift"
  },
  "secrets": {
    "writer_app_key": "github-app-key/millsymills-org-bot-writer",
    "reader_app_key": "github-app-key/millsymills-org-bot-reader"
  }
}
EOF
  log "wrote ${output_file}"
}

write_output_json
```

- [ ] **Step 4: Replace the trailing log line with completion message**

Find the line `log "bootstrap complete (skeleton only)"` and replace with:

```bash
log "AWS bootstrap complete. Next: follow bootstrap/github-bootstrap.md"
```

- [ ] **Step 5: Run all bats tests**

Run: `bats bootstrap/tests/`
Expected: all tests across all files pass.

- [ ] **Step 6: Run shellcheck**

Run: `shellcheck bootstrap/aws-bootstrap.sh bootstrap/lib/_common.sh`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add bootstrap/
git commit -m "feat(bootstrap): add Secrets Manager placeholders and aws-output.json"
```

---

### Task 7: Run AWS bootstrap end-to-end (real apply)

**Files:**
- Read-only verification; will create `bootstrap/aws-output.json` and modify AWS account.

- [ ] **Step 1: Confirm AWS credentials are set and have admin**

Run: `aws sts get-caller-identity`
Expected: returns your admin user/role's `Account`, `Arn`, `UserId`.

- [ ] **Step 2: Run bootstrap in dry-run first**

Run: `./bootstrap/aws-bootstrap.sh --dry-run`
Expected: prints all five phase summaries; exits 0.

- [ ] **Step 3: Run bootstrap for real**

Run: `./bootstrap/aws-bootstrap.sh`
Expected: each phase logs creation; final log line says "AWS bootstrap complete."

- [ ] **Step 4: Verify S3 bucket**

Run: `aws s3api get-bucket-versioning --bucket tfstate-millsymills-com`
Expected: `{"Status": "Enabled", "MFADelete": "Disabled"}`.

Run: `aws s3api get-public-access-block --bucket tfstate-millsymills-com`
Expected: all four blocks `true`.

- [ ] **Step 5: Verify KMS key and rotation**

Run: `aws kms describe-key --key-id alias/tfstate-millsymills --query KeyMetadata.KeyRotationStatus`
Expected: returns key metadata. Then:

Run: `aws kms get-key-rotation-status --key-id alias/tfstate-millsymills`
Expected: `{"KeyRotationEnabled": true}`.

- [ ] **Step 6: Verify all three IAM roles exist with correct trust policy**

Run: `aws iam get-role --role-name gha-millsymills-org-tofu-plan --query Role.AssumeRolePolicyDocument`
Expected: trust policy mentions `environment:tofu-plan` and the OIDC provider.

Repeat for `-apply` and `-drift`.

- [ ] **Step 7: Verify Secrets Manager placeholders**

Run: `aws secretsmanager list-secrets --query "SecretList[?starts_with(Name, 'github-app-key/')].Name"`
Expected: both `millsymills-org-bot-writer` and `millsymills-org-bot-reader`.

- [ ] **Step 8: Inspect `bootstrap/aws-output.json`**

Run: `cat bootstrap/aws-output.json`
Expected: valid JSON with all five top-level fields.

- [ ] **Step 9: Commit `aws-output.json`**

```bash
git add bootstrap/aws-output.json
git commit -m "chore(bootstrap): record AWS resources from initial bootstrap run"
```

---

### Task 8: Document GitHub App creation runbook

**Files:**
- Create: `bootstrap/github-bootstrap.md`

- [ ] **Step 1: Write `bootstrap/github-bootstrap.md`**

```markdown
# GitHub bootstrap runbook

After `aws-bootstrap.sh` completes, perform these manual steps once.

## 1. Customize the org's OIDC subject template

GitHub Actions defaults the OIDC `sub` claim to `repo:OWNER/REPO:ref:REFNAME`.
Customize it so `sub` includes the deployment environment.

```bash
gh api -X PUT /orgs/millsymills-com/actions/oidc/customization/sub \
  -f include_claim_keys[]=repo \
  -f include_claim_keys[]=environment
```

Verify:

```bash
gh api /orgs/millsymills-com/actions/oidc/customization/sub
```

Expected: `{"include_claim_keys": ["repo", "environment"]}`.

Why no `head_ref`: the IAM trust policies generated by `aws-bootstrap.sh` use
`StringEquals` on the full `sub` claim. Adding `head_ref` would change the sub format
to include the source branch and break the trust policy match. Defense against fork PRs
comes from the `repository_id` and `repository_owner_id` claims (immutable), and from
the `environment` claim (only set when the workflow declares an environment, which only
the management repo's workflows do).

## 2. Create the WRITER GitHub App

1. Go to: https://github.com/organizations/millsymills-com/settings/apps/new
2. Fields:
   - GitHub App name: `millsymills-org-bot-writer`
   - Homepage URL: `https://github.com/millsymills-com/millsymills-com-org`
   - Webhook → Active: **unchecked**
3. **Repository permissions:**
   - Administration: Read & Write
   - Contents: Read & Write
   - Metadata: Read-only
   - Pull requests: Read & Write
   - Workflows: Read & Write
   - Issues: Read & Write
   - Pages: Read & Write
   - Variables: Read & Write
   - Secrets: Read & Write
   - Environments: Read & Write
   - Custom properties: Read & Write
4. **Organization permissions:**
   - Administration: Read & Write
   - Members: Read & Write
   - Secrets: Read & Write
   - Variables: Read & Write
   - Plan: Read-only
   - Personal access tokens: Read & Write
5. Where can this GitHub App be installed: **Only on this account**
6. Click **Create GitHub App**.
7. On the next screen, scroll to **Private keys** and click **Generate a private key**. A `.pem` downloads.
8. Note the **App ID** at the top of the page.
9. Click **Install App** in the left sidebar; install on `millsymills-com`, all repositories. Note the **Installation ID** from the URL after install (`https://github.com/organizations/.../settings/installations/<id>`).
10. Upload the key to Secrets Manager:

```bash
aws secretsmanager put-secret-value \
  --secret-id github-app-key/millsymills-org-bot-writer \
  --secret-string "$(cat ~/Downloads/millsymills-org-bot-writer.*.private-key.pem)"
```

11. Securely delete the local file:

```bash
shred -u ~/Downloads/millsymills-org-bot-writer.*.private-key.pem 2>/dev/null \
  || rm -P ~/Downloads/millsymills-org-bot-writer.*.private-key.pem \
  || rm ~/Downloads/millsymills-org-bot-writer.*.private-key.pem
```

## 3. Create the READER GitHub App

Same as step 2 except:

- App name: `millsymills-org-bot-reader`
- All Repository permissions: change Read & Write → **Read-only**, except:
  - Pull requests: **Read & Write** (needed for plan to post PR comments)
- All Organization permissions: change Read & Write → **Read-only** (PAT policy: Read-only).

Upload key:

```bash
aws secretsmanager put-secret-value \
  --secret-id github-app-key/millsymills-org-bot-reader \
  --secret-string "$(cat ~/Downloads/millsymills-org-bot-reader.*.private-key.pem)"
```

Then `shred -u` the local copy.

## 4. Record App IDs and Installation IDs

Create `bootstrap/github-output.json` with values from step 2 and 3:

```json
{
  "org": "millsymills-com",
  "org_id": <numeric>,
  "management_repo": "millsymills-com-org",
  "management_repo_id": <numeric>,
  "writer_app": {
    "name": "millsymills-org-bot-writer",
    "app_id": <numeric>,
    "installation_id": <numeric>
  },
  "reader_app": {
    "name": "millsymills-org-bot-reader",
    "app_id": <numeric>,
    "installation_id": <numeric>
  },
  "oidc_subject_claim_keys": ["repo", "environment"]
}
```

Get numeric org and repo IDs:

```bash
gh api /orgs/millsymills-com --jq .id
gh api /repos/millsymills-com/millsymills-com-org --jq .id
```

## 5. Verify each App can authenticate

For each App (writer, reader), generate a JWT and exchange for an installation token:

```bash
APP_ID=<from-step-4>
INSTALLATION_ID=<from-step-4>
PEM=$(aws secretsmanager get-secret-value \
  --secret-id github-app-key/<app-name> --query SecretString --output text)

NOW=$(date +%s)
HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | openssl base64 -A | tr -d '=' | tr '/+' '_-')
PAYLOAD=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$NOW" "$((NOW+540))" "$APP_ID" \
  | openssl base64 -A | tr -d '=' | tr '/+' '_-')
SIG=$(printf '%s.%s' "$HEADER" "$PAYLOAD" \
  | openssl dgst -sha256 -sign <(printf '%s' "$PEM") -binary \
  | openssl base64 -A | tr -d '=' | tr '/+' '_-')
JWT="$HEADER.$PAYLOAD.$SIG"

curl -s -H "Authorization: Bearer $JWT" \
  -X POST "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" \
  | jq .
```

Expected: a JSON response with a `token` field.

## 6. Commit `bootstrap/github-output.json`

```bash
git add bootstrap/github-output.json
git commit -m "chore(bootstrap): record GitHub App IDs from initial bootstrap"
```
```

- [ ] **Step 2: Commit**

```bash
git add bootstrap/github-bootstrap.md
git commit -m "docs(bootstrap): runbook for GitHub App creation and OIDC subject customization"
```

---

### Task 9: Execute GitHub bootstrap runbook

**Files:**
- Create: `bootstrap/github-output.json`
- Modify: GitHub org settings (subject claim) and create two GitHub Apps.

- [ ] **Step 1: Run the OIDC subject customization (runbook step 1)**

Per `bootstrap/github-bootstrap.md` step 1.

Verify with: `gh api /orgs/millsymills-com/actions/oidc/customization/sub`

Expected: `{"include_claim_keys":["repo","environment","head_ref"]}`.

- [ ] **Step 2: Create writer App via UI (runbook step 2)**

Follow exactly. Verify the App's permissions match the runbook before generating the private key.

- [ ] **Step 3: Upload writer key to Secrets Manager and shred local copy**

Per runbook commands.

- [ ] **Step 4: Create reader App (runbook step 3)**

Follow exactly. Confirm all permissions are Read-only except Pull requests (RW).

- [ ] **Step 5: Upload reader key and shred local copy**

Per runbook.

- [ ] **Step 6: Write `bootstrap/github-output.json`**

Use the structure in runbook step 4. Fill in actual numeric IDs.

- [ ] **Step 7: Verify both Apps authenticate (runbook step 5)**

Run the JWT-exchange snippet for each App. Confirm a `token` is returned for both.

- [ ] **Step 8: Commit `bootstrap/github-output.json`**

```bash
git add bootstrap/github-output.json
git commit -m "chore(bootstrap): record GitHub App IDs and installation IDs"
```

---

## Phase B — Tofu skeleton, import, and baseline modules

### Task 10: Tofu provider, backend, and variables

**Files:**
- Create: `versions.tf`
- Create: `providers.tf`
- Create: `backend.tf`
- Create: `variables.tf`
- Create: `terraform.tfvars` (gitignored — local only)
- Create: `terraform.tfvars.example` (committed)

- [ ] **Step 1: Write `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.4"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.74"
    }
  }
}
```

- [ ] **Step 2: Write `backend.tf`**

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-millsymills-com"
    key          = "millsymills-com-org/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
    kms_key_id   = "alias/tfstate-millsymills"
  }
}
```

- [ ] **Step 3: Write `variables.tf`**

```hcl
variable "org_name" {
  description = "GitHub org slug."
  type        = string
  default     = "millsymills-com"
}

variable "management_repo" {
  description = "Repo slug for the org-as-code management repo."
  type        = string
  default     = "millsymills-com-org"
}

variable "github_app_id" {
  description = "App ID for the GitHub App used in this run (writer or reader)."
  type        = string
}

variable "github_app_installation_id" {
  description = "Installation ID for the GitHub App."
  type        = string
}

variable "github_app_pem_file" {
  description = "Filesystem path to the GitHub App's PEM. CI writes it to ${RUNNER_TEMP} (mode 0600); locally, set to a path you control."
  type        = string
}

variable "aws_region" {
  description = "AWS region for state and KMS."
  type        = string
  default     = "us-east-1"
}
```

- [ ] **Step 4: Write `providers.tf`**

```hcl
provider "github" {
  owner = var.org_name

  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = file(var.github_app_pem_file)
  }
}

provider "aws" {
  region = var.aws_region
}
```

- [ ] **Step 5: Write `terraform.tfvars.example`**

```hcl
# Copy to terraform.tfvars (gitignored) and fill in values from bootstrap/github-output.json.
# Locally, write the PEM to a 0600 file and point github_app_pem_file at it:
#   PEM=$(mktemp); chmod 600 "${PEM}"
#   aws secretsmanager get-secret-value \
#     --secret-id github-app-key/millsymills-org-bot-writer \
#     --query SecretString --output text > "${PEM}"
#   export TF_VAR_github_app_pem_file="${PEM}"

github_app_id              = "<from bootstrap/github-output.json>"
github_app_installation_id = "<from bootstrap/github-output.json>"
# github_app_pem_file is set via TF_VAR_github_app_pem_file env var.
```

- [ ] **Step 6: Create `terraform.tfvars` locally (do NOT commit)**

Confirm `.gitignore` covers `*.tfvars`. Create the file with the actual app_id and installation_id from `bootstrap/github-output.json`.

- [ ] **Step 7: Verify `tofu init` succeeds**

```bash
PEM_FILE=$(mktemp); chmod 600 "${PEM_FILE}"
aws secretsmanager get-secret-value \
  --secret-id github-app-key/millsymills-org-bot-writer \
  --query SecretString --output text > "${PEM_FILE}"
export TF_VAR_github_app_pem_file="${PEM_FILE}"

tofu init
```

Expected: `OpenTofu has been successfully initialized!` and the S3 backend is recognized.

- [ ] **Step 8: Run `tofu validate`**

Run: `tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 9: Commit**

```bash
git add versions.tf providers.tf backend.tf variables.tf terraform.tfvars.example
git commit -m "feat(tofu): provider config, S3 backend, and variables"
```

---

### Task 11: org-baseline module

**Files:**
- Create: `modules/org-baseline/main.tf`
- Create: `modules/org-baseline/variables.tf`
- Create: `modules/org-baseline/outputs.tf`
- Create: `modules/org-baseline/README.md`
- Create: `modules/org-baseline/tests/baseline.tftest.hcl`

- [ ] **Step 1: Write `modules/org-baseline/variables.tf`**

```hcl
variable "org_name" {
  description = "GitHub org slug to manage."
  type        = string
}
```

- [ ] **Step 2: Write `modules/org-baseline/main.tf`**

```hcl
resource "github_organization_settings" "this" {
  billing_email = "mills@millsymills.com"
  name          = "millsymills.com"

  default_repository_permission = "none"

  members_can_create_repositories          = false
  members_can_create_public_repositories   = false
  members_can_create_private_repositories  = false
  members_can_create_internal_repositories = false
  members_can_create_pages                 = false
  members_can_create_public_pages          = false
  members_can_create_private_pages         = false
  members_can_delete_repositories          = false
  members_can_change_repo_visibility       = false
  members_can_invite_outside_collaborators = false
  members_can_delete_issues                = false
  members_can_fork_private_repositories    = false

  web_commit_signoff_required = true

  has_organization_projects = false
  has_repository_projects   = false

  dependabot_alerts_enabled_for_new_repositories                  = true
  dependabot_security_updates_enabled_for_new_repositories        = true
  dependency_graph_enabled_for_new_repositories                   = true
  secret_scanning_enabled_for_new_repositories                    = true
  secret_scanning_push_protection_enabled_for_new_repositories    = true
  advanced_security_enabled_for_new_repositories                  = true
}
```

- [ ] **Step 3: Write `modules/org-baseline/outputs.tf`**

```hcl
output "org_name" {
  value = var.org_name
}
```

- [ ] **Step 4: Write `modules/org-baseline/README.md`**

```markdown
# org-baseline

Codifies organization-wide security settings for `millsymills-com`. These settings
correspond directly to the "Org-wide settings" subsection of the spec.
```

- [ ] **Step 5: Write `modules/org-baseline/tests/baseline.tftest.hcl`**

```hcl
variables {
  org_name = "millsymills-com"
}

run "validate_settings_resource" {
  command = plan

  assert {
    condition     = github_organization_settings.this.default_repository_permission == "none"
    error_message = "default_repository_permission must be 'none'"
  }

  assert {
    condition     = github_organization_settings.this.web_commit_signoff_required == true
    error_message = "web commit signoff must be required"
  }

  assert {
    condition     = github_organization_settings.this.members_can_create_repositories == false
    error_message = "members must not be able to create repositories"
  }
}
```

- [ ] **Step 6: Wire the module into the root `org.tf`**

Create `org.tf`:

```hcl
module "org_baseline" {
  source = "./modules/org-baseline"

  org_name = var.org_name
}
```

- [ ] **Step 7: Run `tofu init` to register the module**

Run: `tofu init`
Expected: module registered.

- [ ] **Step 8: Run `tofu fmt -check -recursive`**

Run: `tofu fmt -check -recursive`
Expected: no changes (or run `tofu fmt -recursive` and re-add).

- [ ] **Step 9: Run module tests**

Run: `tofu test -test-directory=modules/org-baseline/tests`
Expected: 1 test passed.

- [ ] **Step 10: Commit**

```bash
git add modules/org-baseline/ org.tf
git commit -m "feat(tofu): org-baseline module with org-wide settings"
```

---

### Task 12: Import existing org settings (org only, repos in Task 13)

**Files:**
- Create: `imports.tf` (temporary; removed after import)

This task imports only the org-settings resource. Repo imports happen in Task 13 *after*
the `repo-baseline` module exists, so we can import directly into module addresses
without placeholder resources.

- [ ] **Step 1: Write `imports.tf`**

```hcl
import {
  to = module.org_baseline.github_organization_settings.this
  id = "millsymills-com"
}
```

- [ ] **Step 2: Run `tofu plan`**

```bash
tofu plan
```

Expected: import of the org settings. Plan will show diffs where current settings differ
from the baseline (e.g., `default_repository_permission` going from `read` to `none`).
Review each diff carefully — every field changing should match the spec's "Org-wide
settings" section.

- [ ] **Step 3: Apply**

```bash
tofu apply
```

Confirm with `yes`.

- [ ] **Step 4: Verify state**

```bash
tofu state list
```

Expected: includes `module.org_baseline.github_organization_settings.this`.

- [ ] **Step 5: Verify drift = 0**

```bash
tofu plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

- [ ] **Step 6: Remove `imports.tf`**

```bash
rm imports.tf
```

- [ ] **Step 7: Confirm no diff after removal**

Run: `tofu plan`
Expected: still no changes (the import block has done its job; the resource is now in state).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(tofu): import existing org settings into org-baseline module"
```

---

### Task 13: repo-baseline module + import existing repos directly into it

**Files:**
- Create: `modules/repo-baseline/main.tf`
- Create: `modules/repo-baseline/variables.tf`
- Create: `modules/repo-baseline/outputs.tf`
- Create: `modules/repo-baseline/README.md`
- Create: `modules/repo-baseline/tests/baseline.tftest.hcl`
- Modify: `org.tf` to migrate placeholder resources into module calls
- Delete: placeholder `github_repository.existing_*` resources

- [ ] **Step 1: Write `modules/repo-baseline/variables.tf`**

```hcl
variable "name" {
  description = "Repository name."
  type        = string
}

variable "description" {
  description = "Short description shown on the repo page."
  type        = string
  default     = ""
}

variable "visibility" {
  description = "public, private, or internal."
  type        = string
  default     = "public"
  validation {
    condition     = contains(["public", "private", "internal"], var.visibility)
    error_message = "visibility must be public, private, or internal."
  }
}

variable "topics" {
  description = "Repo topics."
  type        = list(string)
  default     = []
}

variable "homepage_url" {
  description = "Homepage shown on the repo page."
  type        = string
  default     = ""
}

variable "has_issues" {
  type    = bool
  default = true
}

variable "archive_on_destroy" {
  description = "If true, the repo is archived rather than deleted on destroy."
  type        = bool
  default     = true
}
```

- [ ] **Step 2: Write `modules/repo-baseline/main.tf`**

```hcl
resource "github_repository" "this" {
  name         = var.name
  description  = var.description
  visibility   = var.visibility
  topics       = var.topics
  homepage_url = var.homepage_url
  has_issues   = var.has_issues
  has_wiki     = false
  has_projects = false

  delete_branch_on_merge = true
  allow_squash_merge     = true
  allow_rebase_merge     = true
  allow_merge_commit     = false
  allow_auto_merge       = false

  vulnerability_alerts        = true
  web_commit_signoff_required = true

  archive_on_destroy = var.archive_on_destroy

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
    advanced_security {
      status = var.visibility == "public" ? "enabled" : "disabled"
    }
  }
}
```

- [ ] **Step 3: Write `modules/repo-baseline/outputs.tf`**

```hcl
output "name" {
  value = github_repository.this.name
}

output "node_id" {
  value = github_repository.this.node_id
}

output "html_url" {
  value = github_repository.this.html_url
}
```

- [ ] **Step 4: Write `modules/repo-baseline/README.md`**

```markdown
# repo-baseline

Default per-repo settings for every repo in the org. Codifies the "Per-repo settings"
subsection of the spec.
```

- [ ] **Step 5: Write `modules/repo-baseline/tests/baseline.tftest.hcl`**

```hcl
variables {
  name        = "test-repo"
  description = "test"
  visibility  = "public"
}

run "defaults_are_safe" {
  command = plan

  assert {
    condition     = github_repository.this.has_wiki == false
    error_message = "wiki must be disabled by default"
  }

  assert {
    condition     = github_repository.this.delete_branch_on_merge == true
    error_message = "delete_branch_on_merge must be true"
  }

  assert {
    condition     = github_repository.this.allow_merge_commit == false
    error_message = "merge commits must be disabled (squash + rebase only)"
  }
}
```

- [ ] **Step 6: Create `repos_existing.tf` (root, not in subdirectory) declaring module instances for each existing repo**

(Note: the file lives at the **repo root** alongside `org.tf`, NOT inside `./repos/`.
OpenTofu only loads `.tf` files from the working directory, not subdirectories, so
files placed in `./repos/` would be silently ignored unless that subdirectory were
declared as a module. Keeping these at root is the simplest correct setup.)

```hcl
locals {
  # NOTE: explicitly exclude the management repo "millsymills-com-org" — it is
  # imported in Task 16 directly into `module.management_repo`. Letting it land
  # here would cause a state-conflict error or, worse, a double-managed repo.
  existing_repos = {
    repo1     = { name = "<existing-public-repo-1-name>",  visibility = "public" }
    repo2     = { name = "<existing-public-repo-2-name>",  visibility = "public" }
    repo3     = { name = "<existing-public-repo-3-name>",  visibility = "public" }
    repo4     = { name = "<existing-public-repo-4-name>",  visibility = "public" }
    repo_priv = { name = "<existing-private-repo-1-name>", visibility = "private" }
    # DO NOT add millsymills-com-org here.
  }
}

module "existing" {
  source   = "./modules/repo-baseline"
  for_each = local.existing_repos

  name       = each.value.name
  visibility = each.value.visibility
}
```

Replace `<existing-...>` placeholders with the actual repo names from
`gh repo list millsymills-com --limit 100 --json name,visibility | jq -r '.[] | select(.name != "millsymills-com-org") | .name'`.

- [ ] **Step 7: Create `repos_imports.tf` (root) with module-aware import blocks**

```hcl
# Import existing repos directly into module instances. No placeholder resources.
# This file is removed after import (Step 13).
import {
  to = module.existing["repo1"].github_repository.this
  id = "<existing-public-repo-1-name>"
}

import {
  to = module.existing["repo2"].github_repository.this
  id = "<existing-public-repo-2-name>"
}

import {
  to = module.existing["repo3"].github_repository.this
  id = "<existing-public-repo-3-name>"
}

import {
  to = module.existing["repo4"].github_repository.this
  id = "<existing-public-repo-4-name>"
}

import {
  to = module.existing["repo_priv"].github_repository.this
  id = "<existing-private-repo-1-name>"
}
```

- [ ] **Step 8: Run module tests**

Run: `tofu test -test-directory=modules/repo-baseline/tests`
Expected: 1 test passed.

- [ ] **Step 9: Run plan and review**

Run: `tofu plan`
Expected: 5 imports + updates to bring settings into baseline. **No destroys.** If
any destroy appears, abort and inspect.

- [ ] **Step 10: Apply**

Run: `tofu apply`
Confirm with `yes`. Each repo's settings are tightened.

- [ ] **Step 11: Verify**

```bash
for repo in $(gh repo list millsymills-com --limit 100 --json name --jq '.[].name'); do
  echo "=== ${repo} ==="
  gh api "/repos/millsymills-com/${repo}" --jq '{
    has_wiki, has_projects, delete_branch_on_merge,
    allow_squash_merge, allow_merge_commit, allow_rebase_merge,
    web_commit_signoff_required, vulnerability_alerts
  }'
done
```

Expected: every repo has has_wiki=false, has_projects=false, delete_branch_on_merge=true,
allow_merge_commit=false, web_commit_signoff_required=true, vulnerability_alerts=true.

- [ ] **Step 12: Verify management repo is NOT in state under module.existing**

`tofu state list` prints resource ADDRESSES (like `module.existing["repo1"].github_repository.this`),
not the `name` attributes of those resources. So a naive `grep millsymills-com-org`
would miss the bug it's trying to catch — namely, the management repo accidentally
imported under a generic key like `repo1`.

Inspect each module instance's actual `name` attribute:

```bash
set -euo pipefail
fail=0
for addr in $(tofu state list | grep -E '^module\.existing\["[^"]+"\]\.github_repository\.this$'); do
  name=$(tofu state show "${addr}" | sed -n 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"\(.*\)"$/\1/p' | head -n 1)
  if [[ "${name}" == "millsymills-com-org" ]]; then
    echo "FAIL: management repo found at ${addr}"
    fail=1
  fi
done
[[ "$fail" -eq 0 ]] && echo "OK: management repo not in module.existing"
exit "$fail"
```

Expected: `OK: management repo not in module.existing` and exit 0. If FAIL, the
management repo was incorrectly imported here; remove its entry from
`local.existing_repos` and `tofu state rm` the wrong address before retrying.

- [ ] **Step 13: Remove `repos_imports.tf`**

```bash
rm repos_imports.tf
```

- [ ] **Step 14: Confirm no diff after removal**

Run: `tofu plan`
Expected: `No changes`.

- [ ] **Step 15: Commit**

```bash
git add modules/repo-baseline/ repos_existing.tf
git commit -m "feat(tofu): repo-baseline module; import existing repos directly into module"
```

---

### Task 14: ruleset-default-branch module

**Files:**
- Create: `modules/ruleset-default-branch/main.tf`
- Create: `modules/ruleset-default-branch/variables.tf`
- Create: `modules/ruleset-default-branch/README.md`
- Modify: `org.tf` (wire it in)

- [ ] **Step 1: Write `modules/ruleset-default-branch/variables.tf`**

```hcl
variable "org_name" {
  type = string
}

variable "ruleset_name" {
  type    = string
  default = "default-branch-protection"
}

variable "required_status_checks" {
  description = "Status check contexts that must pass before merge."
  type        = list(string)
  default     = []
}

variable "required_approving_review_count" {
  type    = number
  default = 0
}
```

- [ ] **Step 2: Write `modules/ruleset-default-branch/main.tf`**

```hcl
resource "github_organization_ruleset" "default_branch" {
  name        = var.ruleset_name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    creation                = false
    update                  = false
    deletion                = true
    required_linear_history = true
    required_signatures     = true

    pull_request {
      dismiss_stale_reviews_on_push   = true
      require_code_owner_review       = true
      require_last_push_approval      = true
      required_approving_review_count = var.required_approving_review_count
      required_review_thread_resolution = true
    }

    dynamic "required_status_checks" {
      for_each = length(var.required_status_checks) > 0 ? [1] : []
      content {
        strict_required_status_checks_policy = true

        dynamic "required_check" {
          for_each = var.required_status_checks
          content {
            context = required_check.value
          }
        }
      }
    }

    non_fast_forward = true
  }

  # Deliberately no bypass_actors. Solo-owner shouldn't have a routine bypass path;
  # if break-glass is ever needed, temporarily set enforcement = "disabled", do the
  # work, set back to "active". Document that procedure in the runbook.
}
```

- [ ] **Step 3: Write `modules/ruleset-default-branch/README.md`**

```markdown
# ruleset-default-branch

Org-wide ruleset that protects every repo's default branch (`~DEFAULT_BRANCH`).
Codifies the "Org-wide rulesets / default-branch-protection" entry of the spec.
```

- [ ] **Step 4: Wire into `org.tf`**

Append to `org.tf`:

```hcl
module "ruleset_default_branch" {
  source = "./modules/ruleset-default-branch"

  org_name = var.org_name
  # No required_status_checks here. The org-wide ruleset applies to ALL repos,
  # most of which won't run tofu/codeql/etc. workflows. Per-repo required checks
  # for the management repo are configured in repos_meta.tf (Task 16a/16b).
  required_status_checks          = []
  required_approving_review_count = 0  # solo-dev caveat (Section 4 of spec)
}
```

- [ ] **Step 5: Plan and review**

Run: `tofu plan`
Expected: creates one `github_organization_ruleset.default_branch` resource. Review the policy carefully.

- [ ] **Step 6: Apply**

Run: `tofu apply`
Confirm.

- [ ] **Step 7: Verify ruleset is active**

```bash
gh api /orgs/millsymills-com/rulesets --jq '.[] | {name, enforcement, target}'
```

Expected: `default-branch-protection` listed with `enforcement: active`, `target: branch`.

- [ ] **Step 8: Commit**

```bash
git add modules/ruleset-default-branch/ org.tf
git commit -m "feat(tofu): default-branch-protection org ruleset (signed commits, linear history, status checks)"
```

---

### Task 15: ruleset-tag-protection module

**Files:**
- Create: `modules/ruleset-tag-protection/main.tf`
- Create: `modules/ruleset-tag-protection/variables.tf`
- Create: `modules/ruleset-tag-protection/README.md`
- Modify: `org.tf` (wire it in)

- [ ] **Step 1: Write `modules/ruleset-tag-protection/variables.tf`**

```hcl
variable "org_name" {
  type = string
}

variable "ruleset_name" {
  type    = string
  default = "tag-protection"
}

variable "tag_pattern" {
  type    = string
  default = "v*"
}
```

- [ ] **Step 2: Write `modules/ruleset-tag-protection/main.tf`**

```hcl
resource "github_organization_ruleset" "tag_protection" {
  name        = var.ruleset_name
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/tags/${var.tag_pattern}"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    creation = false
    update   = true
    deletion = true
  }
}
```

(Note: `update = true` and `deletion = true` here mean the ruleset *blocks* updates and deletions, per the provider's semantics.)

- [ ] **Step 3: Write `modules/ruleset-tag-protection/README.md`**

```markdown
# ruleset-tag-protection

Blocks force-update and deletion of `v*` tags org-wide. Codifies the "tag-protection"
ruleset in the spec.
```

- [ ] **Step 4: Wire into `org.tf`**

```hcl
module "ruleset_tag_protection" {
  source   = "./modules/ruleset-tag-protection"
  org_name = var.org_name
}
```

- [ ] **Step 5: Plan, apply, verify**

Run: `tofu plan && tofu apply`

Verify: `gh api /orgs/millsymills-com/rulesets --jq '.[] | select(.name == "tag-protection")'` returns the ruleset.

- [ ] **Step 6: Commit**

```bash
git add modules/ruleset-tag-protection/ org.tf
git commit -m "feat(tofu): tag-protection ruleset on v* tags"
```

---

### Task 16a: Self-manage `millsymills-com-org` repo + create deployment environments

**Files:**
- Create: `repos_meta.tf` (root)

This task imports the management repo and creates the OIDC deployment environments,
but does NOT yet apply the per-repo required-status-checks ruleset. That happens in
Task 16b after CI is verified end-to-end. Otherwise PRs would be blocked by required
checks that don't exist yet.

- [ ] **Step 1: Write `repos_meta.tf` (root)**

```hcl
import {
  to = module.management_repo.github_repository.this
  id = "millsymills-com-org"
}

module "management_repo" {
  source = "../modules/repo-baseline"

  name        = "millsymills-com-org"
  description = "Org-as-code for millsymills-com. PR-driven, OIDC-enforced."
  visibility  = "public"
  topics      = ["governance", "iac", "opentofu", "supply-chain", "security"]
  homepage_url = "https://github.com/millsymills-com"
}

# Per-repo ruleset adding management-repo-specific required status checks. This
# resource is intentionally NOT in this file at Task 16a; it is added in Task 16b
# (after Task 24 + first verified CI run). Adding it here would block every PR
# because the required check contexts wouldn't yet exist in GitHub's history.

# Deployment environments for OIDC pinning
resource "github_repository_environment" "tofu_plan" {
  repository  = module.management_repo.name
  environment = "tofu-plan"
  # No required reviewers (PR plan must auto-run); see Section 5 of spec.
}

resource "github_repository_environment" "tofu_apply" {
  repository  = module.management_repo.name
  environment = "tofu-apply"
  # Reviewers can be added later for human-in-the-loop apply.
}

resource "github_repository_environment" "tofu_drift" {
  repository  = module.management_repo.name
  environment = "tofu-drift"
}
```

- [ ] **Step 2: Plan, review, apply**

Run: `tofu plan`
Expected: imports `millsymills-com-org` repo and creates three environments. No mutations to repo settings unless drift exists.

Run: `tofu apply`

- [ ] **Step 3: Verify environments exist**

```bash
gh api /repos/millsymills-com/millsymills-com-org/environments --jq '.environments[].name'
```

Expected: `tofu-plan`, `tofu-apply`, `tofu-drift`.

- [ ] **Step 4: Commit**

```bash
git add repos_meta.tf
git commit -m "feat(tofu): self-manage management repo and create OIDC environments"
```

---

## Phase C — CI integration

### Task 17: dependabot.yml

**Files:**
- Create: `.github/dependabot.yml`

- [ ] **Step 1: Write `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: daily
    cooldown:
      default-days: 7
    groups:
      actions:
        patterns: ["*"]

  - package-ecosystem: terraform
    directory: /
    schedule:
      interval: weekly
    cooldown:
      default-days: 7
    groups:
      providers:
        patterns: ["*"]
```

- [ ] **Step 2: Commit**

```bash
git add .github/dependabot.yml
git commit -m "chore: enable dependabot for github-actions and terraform"
```

---

### Task 18: tofu-plan workflow (the PR pipeline)

**Files:**
- Create: `.github/workflows/tofu-plan.yml`

- [ ] **Step 1: Write `.github/workflows/tofu-plan.yml`**

```yaml
name: tofu

on:
  pull_request:
    branches: [main]
    paths:
      - "**/*.tf"
      - "**/*.tfvars.example"
      - ".github/workflows/tofu-*.yml"
      - "modules/**"
      - "repos_*.tf"
      - "org.tf"

permissions:
  contents: read
  id-token: write
  pull-requests: write

concurrency:
  group: tofu-plan-${{ github.ref }}
  cancel-in-progress: true

jobs:
  validate:
    name: validate
    # Runs on EVERY PR including fork PRs. Uncredentialed: no AWS, no App key,
    # no provider API calls. This is the required check; it always actually
    # executes (never skipped), so a fork PR cannot bypass validation by
    # exploiting GitHub's "skipped == passing" semantics.
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - name: Harden runner
        uses: step-security/harden-runner@<PIN-SHA>
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443
            github.com:443
            objects.githubusercontent.com:443
            registry.opentofu.org:443

      - name: Checkout
        uses: actions/checkout@<PIN-SHA>

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@<PIN-SHA>
        with:
          tofu_version: 1.10.3

      - name: Setup tflint
        uses: terraform-linters/setup-tflint@<PIN-SHA>
        with:
          tflint_version: v0.55.1

      - name: tofu fmt -check
        run: tofu fmt -check -recursive

      - name: tofu init (no backend)
        run: tofu init -backend=false -input=false

      - name: tofu validate
        run: tofu validate

      - name: tflint
        run: |
          tflint --init
          tflint --recursive --format=compact

  plan:
    name: plan
    # Credentialed plan: runs only on INTERNAL PRs. Fork PRs skip this job; their
    # required check comes from `validate` above. The OIDC immutable claims
    # describe the BASE workflow file, so they don't distinguish a fork PR run
    # from an internal PR run — the if: guard is the only reliable way to keep
    # AWS creds and the reader App key out of fork-PR-controlled code.
    if: github.event.pull_request.head.repo.full_name == github.repository
    needs: validate
    runs-on: ubuntu-24.04
    environment: tofu-plan
    timeout-minutes: 15

    steps:
      - name: Harden runner
        uses: step-security/harden-runner@<PIN-SHA>  # v2.10.4
        with:
          # block, not audit. Audit-only would let a malicious PR exfiltrate the
          # plan-role credentials or the reader App PEM by simply curl'ing them
          # out before the audit log is shipped. Block enforces the allowlist.
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443
            github.com:443
            objects.githubusercontent.com:443
            registry.opentofu.org:443
            sts.amazonaws.com:443
            s3.us-east-1.amazonaws.com:443
            tfstate-millsymills-com.s3.us-east-1.amazonaws.com:443
            secretsmanager.us-east-1.amazonaws.com:443
            kms.us-east-1.amazonaws.com:443

      - name: Checkout
        uses: actions/checkout@<PIN-SHA>  # v4.2.2
        with:
          fetch-depth: 0

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@<PIN-SHA>  # v1.0.5
        with:
          tofu_version: 1.10.3

      - name: Setup tflint
        uses: terraform-linters/setup-tflint@<PIN-SHA>  # v4.1.1
        with:
          tflint_version: v0.55.1

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@<PIN-SHA>  # v4.0.2
        with:
          role-to-assume: arn:aws:iam::<ACCT>:role/gha-millsymills-org-tofu-plan
          aws-region: us-east-1

      - name: Fetch reader App key to a tempfile
        id: app_key
        run: |
          set -euo pipefail
          # The github provider's app_auth.pem_file expects a filesystem path.
          # We write the PEM to a 0600-mode file under $RUNNER_TEMP and pass its path.
          PEM_FILE="${RUNNER_TEMP}/reader-app.pem"
          umask 077
          aws secretsmanager get-secret-value \
            --secret-id github-app-key/millsymills-org-bot-reader \
            --query SecretString --output text > "${PEM_FILE}"
          chmod 600 "${PEM_FILE}"
          echo "TF_VAR_github_app_pem_file=${PEM_FILE}" >> "${GITHUB_ENV}"
          # Note: rename of writer_pem -> github_app_pem_file is finalized in Task 21.

      - name: tofu init
        run: tofu init -input=false

      - name: tofu plan
        id: plan
        env:
          TF_VAR_github_app_id: ${{ vars.READER_APP_ID }}
          TF_VAR_github_app_installation_id: ${{ vars.READER_INSTALLATION_ID }}
        run: |
          set -euo pipefail
          # Plan to stdout/text only. Do NOT write a binary tfplan to disk in this
          # workflow: tfplan files can serialize sensitive variable values, and the
          # apply workflow re-plans on main rather than reusing this artifact.
          tofu plan -no-color -lock-timeout=120s 2>&1 | tee plan.txt

      - name: Post plan as PR comment
        uses: marocchino/sticky-pull-request-comment@<PIN-SHA>  # v2.9.1
        with:
          header: tofu-plan
          path: plan.txt
```

**Notes:**
- Replace each `<PIN-SHA>` with the SHA of the latest pinned version. Get the SHA via `gh api /repos/<action>/git/refs/tags/<version> --jq '.object.sha'`.
- Replace `<ACCT>` with your AWS account ID from `bootstrap/aws-output.json`.
- Two repository variables (`READER_APP_ID`, `READER_INSTALLATION_ID`) need to be set on the management repo. Set them in Task 22.
- The workflow `name:` is `tofu` and the job `name:` is `plan`, producing a check-run context of `tofu / plan`. The default-branch ruleset's `required_status_checks` references this exact string.
- No `tfplan` binary is written or uploaded; the apply workflow re-plans on `main`. This avoids the risk of leaking the App private key (or any other sensitive variable) through Tofu's plan-file serialization.

- [ ] **Step 2: Look up pinned SHAs**

Run for each action:

```bash
gh api /repos/step-security/harden-runner/git/refs/tags/v2.10.4 --jq '.object.sha'
gh api /repos/actions/checkout/git/refs/tags/v4.2.2 --jq '.object.sha'
gh api /repos/opentofu/setup-opentofu/git/refs/tags/v1.0.5 --jq '.object.sha'
gh api /repos/terraform-linters/setup-tflint/git/refs/tags/v4.1.1 --jq '.object.sha'
gh api /repos/aws-actions/configure-aws-credentials/git/refs/tags/v4.0.2 --jq '.object.sha'
gh api /repos/woodruffw/zizmor-action/git/refs/tags/v0.1.0 --jq '.object.sha'
gh api /repos/marocchino/sticky-pull-request-comment/git/refs/tags/v2.9.1 --jq '.object.sha'
```

Replace each `<PIN-SHA>` placeholder in the workflow with the matching SHA.

- [ ] **Step 3: Run actionlint locally**

Run: `actionlint .github/workflows/tofu-plan.yml`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/tofu-plan.yml
git commit -m "feat(ci): tofu-plan workflow with hardened runner, OIDC, and PR comment"
```

---

### Task 19: tofu-apply workflow (the merge pipeline)

**Files:**
- Create: `.github/workflows/tofu-apply.yml`

- [ ] **Step 1: Write `.github/workflows/tofu-apply.yml`**

```yaml
name: tofu-apply

on:
  push:
    branches: [main]
    paths:
      - "**/*.tf"
      - ".github/workflows/tofu-*.yml"
      - "modules/**"
      - "repos_*.tf"
      - "org.tf"
  workflow_dispatch:

permissions:
  contents: read
  id-token: write

concurrency:
  group: tofu-apply
  cancel-in-progress: false

jobs:
  apply:
    name: apply
    runs-on: ubuntu-24.04
    environment: tofu-apply
    timeout-minutes: 30

    steps:
      - name: Harden runner
        uses: step-security/harden-runner@<PIN-SHA>
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443
            github.com:443
            objects.githubusercontent.com:443
            registry.opentofu.org:443
            sts.amazonaws.com:443
            s3.us-east-1.amazonaws.com:443
            tfstate-millsymills-com.s3.us-east-1.amazonaws.com:443
            secretsmanager.us-east-1.amazonaws.com:443
            kms.us-east-1.amazonaws.com:443

      - name: Checkout
        uses: actions/checkout@<PIN-SHA>
        with:
          fetch-depth: 0

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@<PIN-SHA>
        with:
          tofu_version: 1.10.3

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@<PIN-SHA>
        with:
          role-to-assume: arn:aws:iam::<ACCT>:role/gha-millsymills-org-tofu-apply
          aws-region: us-east-1

      - name: Fetch writer App key to a tempfile
        run: |
          set -euo pipefail
          PEM_FILE="${RUNNER_TEMP}/writer-app.pem"
          umask 077
          aws secretsmanager get-secret-value \
            --secret-id github-app-key/millsymills-org-bot-writer \
            --query SecretString --output text > "${PEM_FILE}"
          chmod 600 "${PEM_FILE}"
          echo "TF_VAR_github_app_pem_file=${PEM_FILE}" >> "${GITHUB_ENV}"

      - name: tofu init
        run: tofu init -input=false

      - name: tofu plan
        env:
          TF_VAR_github_app_id: ${{ vars.WRITER_APP_ID }}
          TF_VAR_github_app_installation_id: ${{ vars.WRITER_INSTALLATION_ID }}
        run: tofu plan -no-color -lock-timeout=120s -out=tfplan

      - name: tofu apply
        env:
          TF_VAR_github_app_id: ${{ vars.WRITER_APP_ID }}
          TF_VAR_github_app_installation_id: ${{ vars.WRITER_INSTALLATION_ID }}
        run: tofu apply -no-color -lock-timeout=120s -auto-approve tfplan

      - name: Cleanup tfplan and pem
        if: always()
        run: |
          rm -f tfplan "${RUNNER_TEMP}/writer-app.pem"
```

Substitute `<PIN-SHA>` and `<ACCT>` per Task 18 step 2.

- [ ] **Step 2: Run actionlint locally**

Run: `actionlint .github/workflows/tofu-apply.yml`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/tofu-apply.yml
git commit -m "feat(ci): tofu-apply workflow on main pushes via OIDC"
```

---

### Task 20: tofu-drift workflow (nightly)

**Files:**
- Create: `.github/workflows/tofu-drift.yml`

- [ ] **Step 1: Write `.github/workflows/tofu-drift.yml`**

```yaml
name: tofu-drift

on:
  schedule:
    - cron: "0 7 * * *"  # 07:00 UTC daily
  workflow_dispatch:

permissions:
  contents: read
  id-token: write
  issues: write

concurrency:
  group: tofu-drift
  cancel-in-progress: false

jobs:
  drift:
    name: drift
    runs-on: ubuntu-24.04
    environment: tofu-drift
    timeout-minutes: 15

    steps:
      - name: Harden runner
        uses: step-security/harden-runner@<PIN-SHA>
        with:
          egress-policy: block
          allowed-endpoints: >
            api.github.com:443
            github.com:443
            objects.githubusercontent.com:443
            registry.opentofu.org:443
            sts.amazonaws.com:443
            s3.us-east-1.amazonaws.com:443
            tfstate-millsymills-com.s3.us-east-1.amazonaws.com:443
            secretsmanager.us-east-1.amazonaws.com:443
            kms.us-east-1.amazonaws.com:443

      - name: Checkout
        uses: actions/checkout@<PIN-SHA>
        with:
          fetch-depth: 0

      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@<PIN-SHA>
        with:
          tofu_version: 1.10.3

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@<PIN-SHA>
        with:
          role-to-assume: arn:aws:iam::<ACCT>:role/gha-millsymills-org-tofu-drift
          aws-region: us-east-1

      - name: Fetch writer App key to a tempfile
        run: |
          set -euo pipefail
          PEM_FILE="${RUNNER_TEMP}/writer-app.pem"
          umask 077
          aws secretsmanager get-secret-value \
            --secret-id github-app-key/millsymills-org-bot-writer \
            --query SecretString --output text > "${PEM_FILE}"
          chmod 600 "${PEM_FILE}"
          echo "TF_VAR_github_app_pem_file=${PEM_FILE}" >> "${GITHUB_ENV}"

      - name: tofu init
        run: tofu init -input=false

      - name: tofu plan -detailed-exitcode
        id: drift_plan
        env:
          TF_VAR_github_app_id: ${{ vars.WRITER_APP_ID }}
          TF_VAR_github_app_installation_id: ${{ vars.WRITER_INSTALLATION_ID }}
        continue-on-error: true
        run: |
          set +e
          tofu plan -no-color -detailed-exitcode -lock-timeout=120s 2>&1 | tee plan.txt
          echo "exitcode=$?" >> "$GITHUB_OUTPUT"

      - name: Open or update drift issue
        if: steps.drift_plan.outputs.exitcode == '2'
        uses: actions/github-script@<PIN-SHA>
        env:
          PLAN_TEXT_PATH: plan.txt
        with:
          script: |
            const fs = require('fs');
            const body = '```\n' + fs.readFileSync(process.env.PLAN_TEXT_PATH, 'utf8').slice(0, 60000) + '\n```';
            const title = 'Drift detected by nightly tofu plan';
            const issues = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              labels: 'drift',
              state: 'open',
            });
            if (issues.data.length > 0) {
              await github.rest.issues.update({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: issues.data[0].number,
                body: body,
              });
            } else {
              await github.rest.issues.create({
                owner: context.repo.owner,
                repo: context.repo.repo,
                title: title,
                body: body,
                labels: ['drift'],
              });
            }

      - name: Open drift-error issue
        if: steps.drift_plan.outputs.exitcode == '1'
        uses: actions/github-script@<PIN-SHA>
        env:
          PLAN_TEXT_PATH: plan.txt
        with:
          script: |
            const fs = require('fs');
            const body = '```\n' + fs.readFileSync(process.env.PLAN_TEXT_PATH, 'utf8').slice(0, 60000) + '\n```';
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: 'Drift workflow error',
              body: body,
              labels: ['drift-error'],
            });

      - name: Fail if drift or error
        if: steps.drift_plan.outputs.exitcode != '0'
        run: exit 1
```

- [ ] **Step 2: Run actionlint**

Run: `actionlint .github/workflows/tofu-drift.yml`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/tofu-drift.yml
git commit -m "feat(ci): nightly tofu-drift workflow that opens issues on drift"
```

---

### Task 21: Split provider variables for reader vs writer

The single `writer_pem` / `writer_app_id` variable served both apply and plan in earlier tasks. Now split them so the plan workflow uses `reader_*` vars and never sees the writer key.

**Files:**
- Modify: `variables.tf`
- Modify: `providers.tf`
- Modify: `.github/workflows/tofu-plan.yml`

- [ ] **Step 1: Update `variables.tf`**

```hcl
variable "org_name" {
  description = "GitHub org slug."
  type        = string
  default     = "millsymills-com"
}

variable "management_repo" {
  description = "Repo slug for the management repo."
  type        = string
  default     = "millsymills-com-org"
}

variable "github_app_id" {
  description = "App ID for the GitHub App that this run is using (writer or reader)."
  type        = string
}

variable "github_app_installation_id" {
  description = "Installation ID for the GitHub App."
  type        = string
}

variable "github_app_pem_file" {
  description = "Filesystem path to the GitHub App's PEM private key. The CI workflows write the PEM to RUNNER_TEMP and pass that path here."
  type        = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}
```

(Note: `pem_file` is the path, not the contents. The variable is not marked `sensitive`
because it carries a path string, not a secret. The actual key material lives on disk
under `${RUNNER_TEMP}` with `0600` perms and is removed at job end.)

- [ ] **Step 2: Update `providers.tf`**

```hcl
provider "github" {
  owner = var.org_name

  app_auth {
    id              = var.github_app_id
    installation_id = var.github_app_installation_id
    pem_file        = file(var.github_app_pem_file)
  }
}

provider "aws" {
  region = var.aws_region
}
```

(The provider's `app_auth.pem_file` argument in some `terraform-provider-github`
versions accepts contents directly and in others requires a path. Wrapping with
`file()` reads the file on the runner, which works across both behaviours and is the
canonical approach.)

- [ ] **Step 3: Confirm workflow env vars match the renamed variables**

Tasks 18, 19, 20 already use `TF_VAR_github_app_id`, `TF_VAR_github_app_installation_id`,
and `TF_VAR_github_app_pem_file` (the latter set from the "Fetch ... App key to a
tempfile" step). Re-skim each workflow to confirm.

- [ ] **Step 4: Run actionlint**

Run: `actionlint .github/workflows/`
Expected: clean.

- [ ] **Step 5: Run `tofu validate` locally**

```bash
PEM_FILE=$(mktemp)
chmod 600 "${PEM_FILE}"
aws secretsmanager get-secret-value \
  --secret-id github-app-key/millsymills-org-bot-writer \
  --query SecretString --output text > "${PEM_FILE}"

export TF_VAR_github_app_id=$(jq -r '.writer_app.app_id' bootstrap/github-output.json)
export TF_VAR_github_app_installation_id=$(jq -r '.writer_app.installation_id' bootstrap/github-output.json)
export TF_VAR_github_app_pem_file="${PEM_FILE}"

tofu validate

shred -u "${PEM_FILE}" 2>/dev/null || rm -P "${PEM_FILE}" || rm "${PEM_FILE}"
```

Expected: `Success!`

- [ ] **Step 6: Commit**

```bash
git add variables.tf providers.tf .github/workflows/
git commit -m "refactor(tofu): use github_app_pem_file (path); workflows write PEM to RUNNER_TEMP"
```

---

### Task 22: Set repo variables for the workflows

**Files:**
- (No file changes; uses `gh` CLI to set repo variables)

- [ ] **Step 1: Read App IDs from `bootstrap/github-output.json`**

```bash
WRITER_APP_ID=$(jq -r '.writer_app.app_id' bootstrap/github-output.json)
WRITER_INSTALL_ID=$(jq -r '.writer_app.installation_id' bootstrap/github-output.json)
READER_APP_ID=$(jq -r '.reader_app.app_id' bootstrap/github-output.json)
READER_INSTALL_ID=$(jq -r '.reader_app.installation_id' bootstrap/github-output.json)
```

- [ ] **Step 2: Set repository variables on the management repo**

```bash
gh variable set WRITER_APP_ID --repo millsymills-com/millsymills-com-org --body "${WRITER_APP_ID}"
gh variable set WRITER_INSTALLATION_ID --repo millsymills-com/millsymills-com-org --body "${WRITER_INSTALL_ID}"
gh variable set READER_APP_ID --repo millsymills-com/millsymills-com-org --body "${READER_APP_ID}"
gh variable set READER_INSTALLATION_ID --repo millsymills-com/millsymills-com-org --body "${READER_INSTALL_ID}"
```

- [ ] **Step 3: Verify**

```bash
gh variable list --repo millsymills-com/millsymills-com-org
```

Expected: all four variables listed.

(No commit — these are server-side state, not tracked files. Document in the runbook step 4 below.)

---

### Task 23: Push everything to the org and trigger the first CI run

**Files:**
- (Push existing commits)

- [ ] **Step 1: Verify the local repo has a clean tree**

Run: `git status`
Expected: clean.

- [ ] **Step 2: Add the org remote**

```bash
git remote add origin https://github.com/millsymills-com/millsymills-com-org.git
git push -u origin main
```

Expected: push succeeds. (If the management repo had any pre-existing commits, expect a non-fast-forward — but per spec we created a fresh repo via Tofu in Task 16, so it should be empty.)

- [ ] **Step 3: Trigger drift workflow manually as the canary**

```bash
gh workflow run tofu-drift.yml --repo millsymills-com/millsymills-com-org
```

Watch:

```bash
gh run watch --repo millsymills-com/millsymills-com-org
```

Expected: drift run completes with exit code 0 (no drift). If it fails:
- Inspect the logs (`gh run view --log`).
- Common bootstrap failures: OIDC trust mismatch, missing env vars, wrong repo IDs in trust policy.

- [ ] **Step 4: Open a no-op test PR**

```bash
git checkout -b test/ci-noop
echo "" >> README.md
git add README.md
git commit -m "test: trigger CI for verification"
git push -u origin test/ci-noop
gh pr create --base main --title "test: verify CI pipeline" --body "Sanity-check the tofu-plan pipeline."
```

- [ ] **Step 5: Watch the PR plan run**

```bash
gh pr checks --watch
```

Expected: `tofu-plan` job succeeds; a sticky comment appears on the PR with the plan output (no changes).

- [ ] **Step 6: Merge the test PR**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 7: Watch the apply run**

```bash
gh run watch --repo millsymills-com/millsymills-com-org
```

Expected: `tofu-apply` runs and completes with exit 0 (apply has nothing to do — that's expected and proves the pipeline works).

- [ ] **Step 8: Pull the merged commit locally**

```bash
git checkout main
git pull --ff-only
```

---

### Task 24: Continuous-security CI workflows on the management repo

**Files:**
- Create: `.github/workflows/codeql.yml`
- Create: `.github/workflows/scorecard.yml`
- Create: `.github/workflows/zizmor.yml`
- Create: `.github/workflows/gitleaks.yml`
- Create: `.github/workflows/actionlint.yml`

- [ ] **Step 1: Write `.github/workflows/codeql.yml`**

```yaml
name: codeql

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: "30 7 * * 1"

permissions:
  contents: read
  security-events: write

jobs:
  analyze:
    name: analyze (${{ matrix.language }})
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    strategy:
      fail-fast: false
      matrix:
        language: [actions]
    steps:
      - uses: step-security/harden-runner@<PIN-SHA>
        with:
          egress-policy: audit
      - uses: actions/checkout@<PIN-SHA>
      - uses: github/codeql-action/init@<PIN-SHA>  # v3
        with:
          languages: ${{ matrix.language }}
      - uses: github/codeql-action/analyze@<PIN-SHA>
```

Check-run context will be `codeql / analyze (actions)`. Matches the ruleset entry.

- [ ] **Step 2: Write `.github/workflows/scorecard.yml`**

```yaml
name: scorecard

on:
  branch_protection_rule:
  schedule:
    - cron: "30 6 * * 1"
  push:
    branches: [main]

permissions:
  read-all

jobs:
  analysis:
    name: analysis
    runs-on: ubuntu-24.04
    permissions:
      security-events: write
      id-token: write
      contents: read
    steps:
      - uses: step-security/harden-runner@<PIN-SHA>
        with:
          egress-policy: audit
      - uses: actions/checkout@<PIN-SHA>
        with:
          persist-credentials: false
      - uses: ossf/scorecard-action@<PIN-SHA>  # v2.4.0
        with:
          results_file: results.sarif
          results_format: sarif
          publish_results: true
      - uses: github/codeql-action/upload-sarif@<PIN-SHA>
        with:
          sarif_file: results.sarif
```

- [ ] **Step 3: Write `.github/workflows/zizmor.yml`**

```yaml
name: zizmor

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
# No paths filter: this is a required check for the management repo, so it
# must run on every PR. zizmor exits 0 if there are no workflows to scan.

permissions:
  contents: read

jobs:
  zizmor:
    name: zizmor
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: step-security/harden-runner@<PIN-SHA>
        with:
          egress-policy: audit
      - uses: actions/checkout@<PIN-SHA>
      - uses: woodruffw/zizmor-action@<PIN-SHA>
        with:
          inputs: ".github/workflows/"
```

- [ ] **Step 4: Write `.github/workflows/gitleaks.yml`**

```yaml
name: gitleaks

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  gitleaks:
    name: gitleaks
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: step-security/harden-runner@<PIN-SHA>
        with:
          egress-policy: audit
      - uses: actions/checkout@<PIN-SHA>
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@<PIN-SHA>  # v2.3.6
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 5: Write `.github/workflows/actionlint.yml`**

```yaml
name: actionlint

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
# No paths filter: required check, must report on every PR.

permissions:
  contents: read

jobs:
  actionlint:
    name: actionlint
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: step-security/harden-runner@<PIN-SHA>
        with:
          egress-policy: audit
      - uses: actions/checkout@<PIN-SHA>
      - uses: raven-actions/actionlint@<PIN-SHA>  # v2.0.0
```

- [ ] **Step 6: Pin all SHAs**

For each new action reference (`github/codeql-action`, `ossf/scorecard-action`, `gitleaks/gitleaks-action`, `raven-actions/actionlint`), look up the SHA via `gh api /repos/<action>/git/refs/tags/<version> --jq '.object.sha'` and replace each `<PIN-SHA>`.

- [ ] **Step 7: Run actionlint locally**

Run: `actionlint .github/workflows/`
Expected: clean.

- [ ] **Step 8: Commit**

```bash
git add .github/workflows/codeql.yml .github/workflows/scorecard.yml .github/workflows/zizmor.yml .github/workflows/gitleaks.yml .github/workflows/actionlint.yml
git commit -m "feat(ci): codeql, scorecard, zizmor, gitleaks, actionlint workflows"
```

- [ ] **Step 9: Push and verify**

```bash
git push
```

Watch the runs:

```bash
gh run list --limit 10
```

Expected: each workflow runs at least once on `main` push and exits 0.

---

### Task 16b: Apply management-repo required-status-checks ruleset

This task is **deferred from Task 16a** until after Task 24 has run and at least one
PR has produced all required check contexts. Applying it earlier would deadlock
every PR on "Expected — Waiting for status to be reported".

**Files:**
- Modify: `repos_meta.tf`

- [ ] **Step 1: Verify all required check contexts have been reported at least once**

```bash
gh api repos/millsymills-com/millsymills-com-org/commits/main/check-runs --jq '.check_runs[] | .name'
```

Expected output should include all of:
- `tofu / plan`
- `zizmor / zizmor`
- `gitleaks / gitleaks`
- `actionlint / actionlint`
- `codeql / analyze (actions)`

If any are missing, do not proceed — open a no-op PR to trigger them, wait for them to
complete, then re-run the check.

- [ ] **Step 2: Append the ruleset resource to `repos_meta.tf`**

```hcl
resource "github_repository_ruleset" "management_repo_checks" {
  name        = "management-repo-checks"
  repository  = module.management_repo.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    required_status_checks {
      strict_required_status_checks_policy = true

      # Required checks must come from JOBS THAT ALWAYS RUN (not jobs that can
      # be skipped by an `if:` guard). GitHub treats a skipped check-run as
      # passing for required-check purposes, so a fork PR could merge with a
      # skipped check.
      required_check { context = "tofu / validate" }          # tofu-plan.yml validate job (uncredentialed, always runs)
      required_check { context = "zizmor / zizmor" }
      required_check { context = "gitleaks / gitleaks" }
      required_check { context = "actionlint / actionlint" }
      required_check { context = "codeql / analyze (actions)" }
      # NOT required: `tofu / plan` is gated to internal PRs only and would
      # report "skipped" on fork PRs (which counts as passing — bypassing the
      # protection). The validate job is the load-bearing required check.
    }
  }
}
```

- [ ] **Step 3: Open a PR with this change**

```bash
git checkout -b feat/management-repo-required-checks
git add repos_meta.tf
git commit -m "feat(tofu): require status checks on management repo default branch"
git push -u origin feat/management-repo-required-checks
gh pr create --base main --title "feat: require status checks on management repo" --body "Activates required-check ruleset now that all contexts have been reported at least once."
```

- [ ] **Step 4: Watch the PR's tofu / plan run**

```bash
gh pr checks --watch
```

Expected: all required checks pass; merge becomes available.

- [ ] **Step 5: Merge the PR**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 6: Verify the ruleset is active**

```bash
gh api /repos/millsymills-com/millsymills-com-org/rulesets --jq '.[] | {name, enforcement, target}'
```

Expected: `management-repo-checks` listed as `active`/`branch`.

- [ ] **Step 7: Verify a deliberately-broken PR is blocked**

Open a PR that breaks `tofu validate` (e.g., adds `invalid hcl ###` to a `.tf` file).
Expected: `tofu / plan` check fails; `Merge` button is disabled.

```bash
git checkout -b test/break-validate
echo 'invalid hcl ###' > broken.tf
git add broken.tf
git commit -m "test: should fail validate"
git push -u origin test/break-validate
gh pr create --title "test: validate should fail" --body "Expected failure."
gh pr checks --watch
```

After confirmation, close and clean up:

```bash
gh pr close --delete-branch
git checkout main
git branch -D test/break-validate
```

---

### Task 25: Lock down management repo access (revoke local admin AWS creds)

**Files:**
- (Configuration on developer machine; documented in runbook)

- [ ] **Step 1: Document the lockdown step in `bootstrap/github-bootstrap.md`**

Append to the runbook:

```markdown
## 7. Post-bootstrap lockdown

After CI is verified working end-to-end:

1. Reduce local AWS credentials to read-only or revoke the admin user/role used during bootstrap.
2. Verify you can no longer mutate state from the local CLI.

Test:

```bash
aws s3api put-bucket-policy --bucket tfstate-millsymills-com --policy '{}' 2>&1
```

Expected: `AccessDenied`.
```

- [ ] **Step 2: Apply the lockdown locally**

Per the runbook step 7. Replace your `~/.aws/credentials` admin profile with a read-only one (or revoke entirely).

- [ ] **Step 3: Verify**

```bash
aws sts get-caller-identity
```

Expected: returns a non-admin identity.

```bash
aws iam attach-role-policy --role-name gha-millsymills-org-tofu-plan --policy-arn arn:aws:iam::aws:policy/AdministratorAccess 2>&1
```

Expected: `AccessDenied`.

- [ ] **Step 4: Commit the runbook update**

```bash
git add bootstrap/github-bootstrap.md
git commit -m "docs(bootstrap): lockdown procedure for post-CI-verification"
```

---

### Task 26: Self-disable bootstrap

**Files:**
- Create: `bootstrap/.disabled`

- [ ] **Step 1: Verify the canary tests pass one final time**

Run via UI: `gh workflow run tofu-drift.yml`. Wait for completion.
Expected: green; no drift.

- [ ] **Step 2: Write the sentinel**

```bash
COMMIT_SHA=$(git rev-parse HEAD)
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > bootstrap/.disabled <<EOF
# bootstrap completed
date: ${DATE}
commit: ${COMMIT_SHA}
operator: millsmillsymills

Manual re-runs require --force and a new runbook entry.
EOF
```

- [ ] **Step 3: Verify the script refuses to run**

Run: `./bootstrap/aws-bootstrap.sh --dry-run`
Expected: exits non-zero with "refusing to run".

- [ ] **Step 4: Verify --force still works**

Run: `./bootstrap/aws-bootstrap.sh --dry-run --force`
Expected: exits 0.

- [ ] **Step 5: Commit**

```bash
git add bootstrap/.disabled
git commit -m "chore(bootstrap): seal bootstrap; future runs require --force"
git push
```

---

## Phase D — Plan-1 verification & handoff

### Task 27: End-to-end verification

- [ ] **Step 1: Verify org settings match baseline**

```bash
gh api /orgs/millsymills-com --jq '{
  default_repository_permission,
  members_can_create_repositories,
  members_can_delete_repositories,
  members_can_change_repo_visibility,
  web_commit_signoff_required,
  two_factor_requirement_enabled,
  dependabot_alerts_enabled_for_new_repositories,
  secret_scanning_enabled_for_new_repositories,
  secret_scanning_push_protection_enabled_for_new_repositories
}'
```

Expected: all match baseline (`default_repository_permission = "none"`, members_can_* false, web_commit_signoff_required true, alerts/scanning enabled).

- [ ] **Step 2: Verify org rulesets are active**

```bash
gh api /orgs/millsymills-com/rulesets --jq '.[] | {name, target, enforcement}'
```

Expected: `default-branch-protection` (branch, active) + `tag-protection` (tag, active).

- [ ] **Step 3: Verify all 5 existing repos conform to baseline**

```bash
for repo in $(gh repo list millsymills-com --limit 100 --json name --jq '.[].name'); do
  echo "=== ${repo} ==="
  gh api "/repos/millsymills-com/${repo}" --jq '{
    name, has_wiki, delete_branch_on_merge,
    allow_squash_merge, allow_merge_commit,
    web_commit_signoff_required, vulnerability_alerts
  }'
done
```

Expected: every repo has has_wiki=false, delete_branch_on_merge=true, allow_merge_commit=false, web_commit_signoff_required=true, vulnerability_alerts=true.

- [ ] **Step 4: Verify drift workflow has run successfully at least once**

```bash
gh run list --workflow=tofu-drift.yml --limit 1 --json conclusion,createdAt
```

Expected: `conclusion: success`.

- [ ] **Step 5: Verify required status checks block a failing PR**

This was performed in Task 16b Step 7 (after the management-repo-checks ruleset was activated). If you skipped that verification, run it now.

- [ ] **Step 6: Verify local apply is now blocked**

Run (with current non-admin AWS creds):

```bash
TF_VAR_github_app_id=$(jq -r '.writer_app.app_id' bootstrap/github-output.json) \
TF_VAR_github_app_installation_id=$(jq -r '.writer_app.installation_id' bootstrap/github-output.json) \
TF_VAR_github_app_pem="<unset>" tofu apply 2>&1 || true
```

Expected: error reading App key (Secrets Manager AccessDenied) — confirms locked-out admin.

- [ ] **Step 7: Final summary**

Document Plan-1 completion:

```bash
cat > docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md <<EOF
# Plan 1 — Bootstrap + Baseline: completed

Completion date: $(date -u +%Y-%m-%d)
Final commit: $(git rev-parse HEAD)

Verified:
- AWS bootstrap resources (S3, KMS, IAM, Secrets Manager) created and locked.
- Two GitHub Apps created; private keys stored in Secrets Manager.
- Org-baseline applied; all org-wide settings conformant.
- repo-baseline applied; all 5 existing repos conformant.
- Both org rulesets (default-branch-protection, tag-protection) active.
- CI works end-to-end: PR plan posts comment; merge applies; nightly drift runs.
- Local admin AWS creds revoked; bootstrap script self-disabled.
- Failing PRs are blocked by required status checks.

Next: Plan 2 (portfolio repos: .github, controls-as-code, terraform-aws-baseline,
incident-response-runbooks) and content (READMEs, ADRs, runbooks).
EOF
git add docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md
git commit -m "docs: record Plan-1 completion"
git push
```

---

## Self-review (run before declaring plan complete)

Spec coverage:
- Section 1 (architecture) — Tasks 10-16 build the pieces; Task 23 + Task 27 verify end-to-end.
- Section 2 (security baseline) — org-wide settings: Task 11; rulesets: Tasks 14-15; per-repo: Task 13; per-repo files (SECURITY.md, CODEOWNERS, dependabot.yml): Tasks 1, 17. **Note:** per-repo CodeQL/scorecard/zizmor on *new* portfolio repos is deferred to Plan 2 — Plan 1 covers them only on the management repo (Task 24).
- Section 3 (repo structure) — directory layout in Task 1; the four MVP non-`.github` portfolio repos are Plan 2.
- Section 4 (CI/CD) — Tasks 18 (plan), 19 (apply), 20 (drift), 24 (continuous-security), 25-26 (lockdown).
- Section 5 (auth) — Phase A (1-9). Task 21 splits reader/writer cleanly. Trust policies in Task 5 use environment-pinned `sub`.
- Section 6 (bootstrap) — Tasks 1-9 + 26.
- Section 7 (portfolio narrative) — Plan 2.
- Open questions — none of these block Plan 1; they all surface in Plan 2 (`millsymills.com` tie-in, FUNDING.yml, etc.).

Placeholder scan:
- `<PIN-SHA>` placeholders are explicitly marked as "fill in via this command" in Task 18 step 2. Treated as a deliberate parametric value, not a placeholder.
- `<ACCT>`, `<existing-...-repo-...-name>` — same; explicit lookup commands provided.
- `actor_id = 1` in `ruleset-default-branch/main.tf` is a known provider-specific magic number for `OrganizationAdmin`; verify against `terraform-provider-github` docs at implementation time and adjust if the schema has shifted.

Type / name consistency:
- `TF_VAR_writer_*` variables in Tasks 18-20 are renamed to `TF_VAR_github_app_*` in Task 21; Task 21 is the consolidation point and re-touches all three workflows.
- IAM role names `gha-millsymills-org-tofu-{plan,apply,drift}` are consistent across Task 5, Task 18, Task 19, Task 20, and the spec.
- Module names (`org-baseline`, `repo-baseline`, `ruleset-default-branch`, `ruleset-tag-protection`) match the spec's directory layout.

---

## Known limitations of Plan 1

- **Provider versions:** `terraform-provider-github` v6 has known schema churn around rulesets. If `bypass_actors.actor_id = 1` is rejected, look up the current numeric ID via the API and use that.
- **Solo-dev required-reviewer:** `required_approving_review_count = 0` because GitHub Free + solo dev. Plan 2 adds an environment-protection rule on `tofu-apply` that requires manual approval as a defense-in-depth substitute.
- **No SLSA-3 attestation in Plan 1:** SBOM + provenance attestation is set up in Plan 2 alongside the portfolio repos (which are the things that release artifacts).
- **`millsymills.com` tie-in not addressed:** Plan 2.

---

## Validation changelog

### 2026-05-09 — Round 4: verification spot-check on round-3 fixes

| # | Finding | Source | Resolution |
|---|---|---|---|
| 16 | Skipped jobs satisfy required checks. The round-3 fix gated the credentialed plan job with `if: github.event.pull_request.head.repo.full_name == github.repository`, but GitHub treats a skipped check-run as passing for required-check purposes. A fork PR could therefore merge with no validation. | codex:review v4 | Split `tofu-plan.yml` into two jobs: `validate` (uncredentialed, runs on every PR including forks — does fmt/init/validate/tflint without provider auth) and `plan` (credentialed, internal PRs only). Required check changed to `tofu / validate` (always runs, never skipped). `tofu / plan` is no longer required; it's informational. |
| 17 | State-verification command in Task 13 Step 12 (`tofu state list \| grep millsymills-com-org`) searches resource ADDRESSES not repo names. If the management repo were accidentally imported under key `repo1`, grep returns empty and the check falsely passes. | codex:review v4 | Replaced with a loop that calls `tofu state show` on each `module.existing[*].github_repository.this` address and parses out the actual `name` attribute, comparing each to `millsymills-com-org`. Exits non-zero if found anywhere. |

---

### 2026-05-09 — Round 3: post-fix verification pass

After Round 2 fixes were applied, both reviewers were re-run against the v2 plan. Five new legitimate findings emerged from the post-fix pass; all are now addressed.

| # | Finding | Source | Resolution |
|---|---|---|---|
| 11 | Fork PRs can still get plan role + reader App key. The new `repository_id`/`repository_owner_id`/`job_workflow_ref` claims describe the BASE repo and base workflow file — they do NOT distinguish a fork-PR run (which uses the base workflow) from an internal-PR run. | adversarial v3 | Plan job now gated by `if: github.event.pull_request.head.repo.full_name == github.repository`, which skips the credentialed job for fork PRs entirely. `harden-runner` switched from `egress-policy: audit` to `egress-policy: block` on all credentialed jobs (plan, apply, drift) so even an unexpected breakout cannot exfiltrate to non-allowlisted hosts. |
| 12 | Required-check ruleset listed `zizmor / zizmor`, `actionlint / actionlint`, and `scorecard / analysis`, but those workflows had path filters or non-PR triggers — for many PRs, those checks would never run, leaving GitHub at "Expected" forever. Combined with the no-bypass posture from #6, the repo could lock itself out of merges. | adversarial v3 | Removed path filters from `zizmor.yml` and `actionlint.yml`; both now run on every `pull_request: branches: [main]`. Removed `scorecard / analysis` from the required-check list (it's a scheduled scoring tool, not a per-PR check). |
| 13 | Management repo could be double-imported: Task 13's `gh repo list` includes it, and Task 16 also imports it. State conflict. | adversarial v3 | `local.existing_repos` in Task 13 explicitly excludes `millsymills-com-org` with a comment. The `gh repo list` example in the runbook now pipes through `jq` to filter it out. Task 13 Step 12 verifies it is NOT in state under `module.existing` before proceeding. |
| 14 | `repos/_existing.tf` and `repos/_imports.tf` would not be loaded by root `tofu plan` — OpenTofu reads `.tf` files from the working directory only, not subdirectories. The whole import path would silently no-op. | codex:review v3 | Files moved to root: `repos_existing.tf`, `repos_imports.tf`, `repos_meta.tf`. Module `source = "./modules/repo-baseline"` (no longer `../`). Directory layout note in Task 1 updated. |
| 15 | The required-check ruleset was being applied in Task 16 (before Tasks 18-20, 24 had run); GitHub would mark required checks as "Expected" with no run history, blocking every subsequent PR. | codex:review v3 + adversarial v3 | Task 16 split into 16a (repo + environments only, no ruleset) and 16b (ruleset, applied after Task 24 + first verified CI run). Task 16b includes a check-runs verification step before activating the ruleset, plus the failing-PR test that was previously in Task 27. |

---

### 2026-05-09 — Round 2: Codex review + adversarial review pass

| # | Finding | Source | Resolution |
|---|---|---|---|
| 1 | OIDC subject template included `head_ref`; trust policy used `StringEquals` without it → assume-role would fail | both reviews + pre-validation | Removed `head_ref` from `include_claim_keys` in Task 8 runbook; subject template now `[repo, environment]`. Trust policy unchanged. |
| 2 | Trust policy missing `repository_id`, `repository_owner_id`, `job_workflow_ref` (spec required) | adversarial | Bootstrap script (Task 5) now looks up org and repo IDs via `gh api` and emits a trust policy with `StringEquals` on `repository_id` + `repository_owner_id` and `StringLike` on `job_workflow_ref` pinning each role to its specific workflow file on `refs/heads/main`. |
| 3 | Plan + drift roles read-only against S3 but `use_lockfile = true` requires lock-file writes | both reviews | Base IAM policy (Task 5) now grants `s3:PutObject`/`s3:DeleteObject` scoped to `*.tflock` only, plus `kms:Encrypt`/`kms:GenerateDataKey` for the lock-file ciphertext. Apply role retains its broader writes. |
| 4 | `pem_file` in provider expects a path; workflows put PEM contents in env var | adversarial | Workflows (Tasks 18, 19, 20) now write the PEM to `${RUNNER_TEMP}/<role>-app.pem` with mode `0600`, pass the path through `TF_VAR_github_app_pem_file`, and `providers.tf` calls `file(var.github_app_pem_file)`. Apply workflow has a final `if: always()` cleanup step. |
| 5 | Required-check names didn't match actual check-run contexts | adversarial | Every workflow job now has an explicit `name:` (`plan`, `apply`, `drift`, `analyze (actions)`, `analysis`, `zizmor`, `gitleaks`, `actionlint`); ruleset references match. Org-wide ruleset (Task 14) no longer carries `required_status_checks`; per-repo ruleset on the management repo (Task 16) carries them, scoped to the repo that actually runs the checks. |
| 6 | `bypass_actors` granted OrganizationAdmin a PR-bypass | adversarial | Removed entirely. Break-glass is now: temporarily set `enforcement = "disabled"`, do the work, set back to `"active"`. To be documented as a runbook in Plan 2. |
| 7 | `tfplan` artifact upload could leak App PEM via Tofu plan-file serialization | codex:review | Removed `-out=tfplan` and the artifact upload step from the PR workflow (Task 18). The PR comment carries the human-readable plan; apply re-plans on `main`. |
| 8 | Task 12's `rm imports.tf` orphaned Task 13's `moved` blocks → repos would be destroyed | pre-validation | Restructured: Task 12 imports only org settings; Task 13 defines the `repo-baseline` module first, then uses module-aware `import` blocks (`to = module.existing["repoN"].github_repository.this`) — no placeholder resources, no `moved` blocks needed. |
| 9 | `--max-session-duration 900` (15 min) too short for long applies | pre-validation | Bumped to `3600` in Task 5. |
| — | Org-wide required-status-checks would deadlock PRs on non-management repos that don't run tofu/codeql/etc. | discovered while applying fix #5 | Required checks moved from the org-wide ruleset onto a per-repo `github_repository_ruleset` in Task 16, scoped only to the management repo. |

All findings address legitimate issues in the original plan. None were false positives.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
