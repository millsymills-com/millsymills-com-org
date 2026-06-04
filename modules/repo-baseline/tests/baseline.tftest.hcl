mock_provider "github" {}

variables {
  name        = "test-repo"
  description = "test"
  visibility  = "public"
}

run "defaults_are_safe" {
  command = plan

  assert {
    condition     = github_repository.this.has_wiki == false
    error_message = "wiki must be disabled by default"
  }

  assert {
    condition     = github_repository.this.delete_branch_on_merge == true
    error_message = "delete_branch_on_merge must be true"
  }

  assert {
    condition     = github_repository.this.allow_merge_commit == false
    error_message = "merge commits must be disabled (squash + rebase only)"
  }

  assert {
    condition     = github_repository_vulnerability_alerts.this.enabled == true
    error_message = "vulnerability alerts must be enabled via sibling resource"
  }

  assert {
    condition     = github_repository.this.auto_init == false
    error_message = "auto_init must default to false (imported repos must not be re-initialized)"
  }
}

run "auto_init_can_be_enabled" {
  command = plan

  variables {
    auto_init = true
  }

  assert {
    condition     = github_repository.this.auto_init == true
    error_message = "auto_init must be settable for tofu-created repos"
  }
}
