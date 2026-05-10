mock_provider "github" {}

run "validate_settings_resource" {
  command = plan

  assert {
    condition     = module.org_baseline.settings.default_repository_permission == "none"
    error_message = "default_repository_permission must be 'none'"
  }

  assert {
    condition     = module.org_baseline.settings.web_commit_signoff_required == true
    error_message = "web commit signoff must be required"
  }

  assert {
    condition     = module.org_baseline.settings.members_can_create_repositories == false
    error_message = "members must not be able to create repositories"
  }

  assert {
    condition     = module.org_baseline.settings.dependabot_alerts_enabled_for_new_repositories == true
    error_message = "dependabot alerts must be enabled by default for new repos"
  }

  assert {
    condition     = module.org_baseline.settings.secret_scanning_push_protection_enabled_for_new_repositories == true
    error_message = "secret scanning push protection must be enabled by default for new repos"
  }
}
