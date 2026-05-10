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

log "bootstrap complete (skeleton only)"
