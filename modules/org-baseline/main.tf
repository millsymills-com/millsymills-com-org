resource "github_organization_settings" "this" {
  billing_email = var.billing_email
  name          = var.display_name

  default_repository_permission = "none"

  members_can_create_repositories          = false
  members_can_create_public_repositories   = false
  members_can_create_private_repositories  = false
  members_can_create_internal_repositories = false
  members_can_create_pages                 = false
  members_can_create_public_pages          = false
  members_can_create_private_pages         = false
  members_can_fork_private_repositories    = false

  web_commit_signoff_required = true

  has_organization_projects = false
  has_repository_projects   = false

  dependabot_alerts_enabled_for_new_repositories               = true
  dependabot_security_updates_enabled_for_new_repositories     = true
  dependency_graph_enabled_for_new_repositories                = true
  secret_scanning_enabled_for_new_repositories                 = true
  secret_scanning_push_protection_enabled_for_new_repositories = true
  # Advanced Security is a paid GHAS product (Enterprise Cloud + per-seat licenses).
  # On Free plans, GitHub silently ignores a `true` here. Public repos still get
  # secret scanning, push protection, and dependency review for free — those are
  # the spec's actual security signals; the `advanced_security_*` flag is not.
  advanced_security_enabled_for_new_repositories = false
}

# Four org settings the integrations/github v6 provider does not surface via
# github_organization_settings:
#   - members_can_delete_repositories
#   - members_can_change_repo_visibility
#   - members_can_invite_outside_collaborators
#   - members_can_delete_issues
# These are enforced one-time via scripts/set-extra-org-settings.sh and tracked
# by drift detection (see modules/drift-extra-settings or the runbook).
