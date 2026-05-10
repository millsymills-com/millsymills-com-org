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

log "bootstrap complete (skeleton only)"
