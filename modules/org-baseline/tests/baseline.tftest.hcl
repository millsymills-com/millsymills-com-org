mock_provider "github" {}

variables {
  org_name      = "millsymills-com"
  billing_email = "mills@millsymills.com"
  display_name  = "millsymills.com"
  description   = "MCP servers and security-hardened org-as-code. Built by Andrew Mills."
  blog          = "https://millsymills.com"
  location      = "Pacific Northwest — Remote"
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

  assert {
    condition     = github_organization_settings.this.dependabot_alerts_enabled_for_new_repositories == true
    error_message = "dependabot alerts must be enabled by default for new repos"
  }

  assert {
    condition     = github_organization_settings.this.secret_scanning_push_protection_enabled_for_new_repositories == true
    error_message = "secret scanning push protection must be enabled by default for new repos"
  }

  assert {
    condition     = github_organization_settings.this.description == "MCP servers and security-hardened org-as-code. Built by Andrew Mills."
    error_message = "public org description must render"
  }

  assert {
    condition     = github_organization_settings.this.blog == "https://millsymills.com"
    error_message = "public org website must render"
  }

  assert {
    condition     = github_organization_settings.this.location == "Pacific Northwest — Remote"
    error_message = "public org location must render"
  }
}
