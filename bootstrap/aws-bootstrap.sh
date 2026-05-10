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

# ---------------------------------------------------------------------
# Phase 1.2: KMS key for state encryption
# ---------------------------------------------------------------------

KMS_ALIAS="${KMS_ALIAS:-alias/tfstate-millsymills}"

create_state_kms_key() {
  log "would create KMS key: ${KMS_ALIAS}"
  log "  - annual rotation: enabled"
  log "  - deletion window: 30 days"
  log "  - admin: account root + caller IAM identity (break-glass)"
  log "would apply bucket policy on ${STATE_BUCKET}: deny non-TLS, deny non-KMS writes"

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

# KMS_KEY_ARN is populated by create_state_kms_key in non-dry-run mode.
# Default to empty so the heredocs below evaluate cleanly under set -u.
KMS_KEY_ARN="${KMS_KEY_ARN:-}"

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

log "bootstrap complete (skeleton only)"
