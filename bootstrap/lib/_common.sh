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
