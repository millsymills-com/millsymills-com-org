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
    condition     = github_repository_vulnerability_alerts.this.enabled == true
    error_message = "vulnerability alerts must be enabled via sibling resource"
  }

  assert {
    condition     = github_repository.this.web_commit_signoff_required == true
    error_message = "web commit signoff must be required"
  }
}

run "merge_methods_stay_signable" {
  command = plan

  assert {
    condition     = github_repository.this.allow_squash_merge == true
    error_message = "squash must stay enabled; it is the only signed merge method left"
  }

  # Not style: a rebase merge lands commits GitHub cannot sign, and the
  # default-branch ruleset's required_signatures then rejects them.
  assert {
    condition     = github_repository.this.allow_rebase_merge == false
    error_message = "rebase merges must be disabled (unsigned commits fail required_signatures)"
  }

  assert {
    condition     = github_repository.this.allow_merge_commit == false
    error_message = "merge commits must be disabled (squash only)"
  }

  assert {
    condition     = github_repository.this.allow_auto_merge == true
    error_message = "auto-merge capability must be on for Renovate platformAutomerge (ADR-0007)"
  }
}
