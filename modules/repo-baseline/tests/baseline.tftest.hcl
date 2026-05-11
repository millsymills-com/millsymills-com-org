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
}
