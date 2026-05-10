#!/usr/bin/env bash
# Attempt to set org-level settings that integrations/github v6 doesn't surface
# via github_organization_settings. **GitHub silently ignores writes to most of
# these via the PATCH /orgs/{org} endpoint as of 2026** — they were moved to the
# consolidated member-privileges UI / Code Security Configurations. The PATCH
# still returns 200 OK with the request body merged into the response object,
# but the new values are not persisted.
#
# This script tries the PATCH anyway (cheap, no-op on success-but-not-stored
# fields), then READS the current state and emits warnings for any field that
# is not at the desired value. The operator must set un-storable fields via
# the web UI: https://github.com/organizations/<org>/settings/member_privileges
#
# Fields covered:
#   members_can_delete_repositories         -> false   [UI required as of 2026]
#   members_can_change_repo_visibility      -> false   [UI required as of 2026]
#   members_can_invite_outside_collaborators -> false  [UI required as of 2026]
#   members_can_delete_issues               -> false   (often already default)
#   two_factor_requirement_enabled          -> true    [UI required as of 2026]
#
# Exits 0 if all values are at desired state, 1 otherwise.
set -euo pipefail

ORG="${1:-millsymills-com}"

echo "Attempting PATCH on /orgs/${ORG}..."
gh api -X PATCH "/orgs/${ORG}" \
    -F members_can_delete_repositories=false \
    -F members_can_change_repo_visibility=false \
    -F members_can_invite_outside_collaborators=false \
    -F members_can_delete_issues=false \
    -F two_factor_requirement_enabled=true \
    >/dev/null
echo "PATCH returned 200 OK. Reading actual current state..."

ACTUAL=$(gh api "/orgs/${ORG}" --jq '{
  members_can_delete_repositories,
  members_can_change_repo_visibility,
  members_can_invite_outside_collaborators,
  members_can_delete_issues,
  two_factor_requirement_enabled
}')
echo "${ACTUAL}"

DRIFT=0
check() {
    local field="$1" expected="$2"
    local actual
    actual=$(echo "${ACTUAL}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['${field}']))")
    if [[ "${actual}" != "${expected}" ]]; then
        echo "  ⚠ ${field}: ${actual} (want ${expected}) — set via UI: https://github.com/organizations/${ORG}/settings/member_privileges"
        DRIFT=1
    fi
}

check members_can_delete_repositories          false
check members_can_change_repo_visibility       false
check members_can_invite_outside_collaborators false
check members_can_delete_issues                false
check two_factor_requirement_enabled           true

if [[ "${DRIFT}" -eq 1 ]]; then
    echo "Drift detected on at least one field. Set the listed fields via the org's web UI."
    exit 1
fi

echo "All target fields at desired state."
