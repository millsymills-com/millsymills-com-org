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
