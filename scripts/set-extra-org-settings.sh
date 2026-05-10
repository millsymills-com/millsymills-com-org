#!/usr/bin/env bash
# Set the four org settings that integrations/github v6 doesn't surface via
# github_organization_settings:
#   - members_can_delete_repositories
#   - members_can_change_repo_visibility
#   - members_can_invite_outside_collaborators
#   - members_can_delete_issues
#
# Idempotent. Settings already at the desired values are no-ops on the server.
# Re-run any time drift is detected.
#
# Requires: gh CLI authenticated as an org owner (or via the writer App's PAT).
set -euo pipefail

ORG="${1:-millsymills-com}"

echo "Setting extra org-level security settings on ${ORG}..."

gh api -X PATCH "/orgs/${ORG}" \
    -F members_can_delete_repositories=false \
    -F members_can_change_repo_visibility=false \
    -F members_can_invite_outside_collaborators=false \
    -F members_can_delete_issues=false \
    >/dev/null

echo "Done. Verify:"
gh api "/orgs/${ORG}" --jq '{
  members_can_delete_repositories,
  members_can_change_repo_visibility,
  members_can_invite_outside_collaborators,
  members_can_delete_issues
}'
