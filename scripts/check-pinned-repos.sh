#!/usr/bin/env bash
# Org pinned repositories have no REST/GraphQL/Terraform write surface — like the
# member-privilege fields in set-extra-org-settings.sh, they can only be set from
# the web UI: https://github.com/orgs/<org> -> "Customize your organization's
# profile" -> Pinned repositories.
#
# This script READS the current pins via GraphQL and flags drift against the
# desired set below. It does not (cannot) write. The operator pins the listed
# repos, in order, via the UI.
#
# Desired pins, in display order:
#   1. millsymills-com-org   (org-as-code / security posture)
#   2. unraid-mcp
#   3. unifi-mcp
#   4. gandi-mcp
#   5. protonmail-mcp
#   6. flipperzero-mcp
#
# Exits 0 if the current pin set matches the desired set, 1 otherwise.
set -euo pipefail

ORG="${1:-millsymills-com}"

DESIRED=(millsymills-com-org unraid-mcp unifi-mcp gandi-mcp protonmail-mcp flipperzero-mcp)

ACTUAL=$(gh api graphql -f query="
{
  organization(login: \"${ORG}\") {
    pinnedItems(first: 6, types: REPOSITORY) {
      nodes { ... on Repository { name } }
    }
  }
}" --jq '.data.organization.pinnedItems.nodes[].name')

echo "Currently pinned:"
if [[ -z "${ACTUAL}" ]]; then
  echo "  (none)"
else
  while IFS= read -r line; do echo "  ${line}"; done <<<"${ACTUAL}"
fi

DRIFT=0
for repo in "${DESIRED[@]}"; do
  if ! grep -qx "${repo}" <<<"${ACTUAL}"; then
    echo "  ⚠ ${repo} is not pinned"
    DRIFT=1
  fi
done

if [[ "${DRIFT}" -eq 1 ]]; then
  echo "Pin the repos listed above (in order) via the org profile UI: https://github.com/orgs/${ORG}"
  exit 1
fi

echo "All desired repos are pinned."
