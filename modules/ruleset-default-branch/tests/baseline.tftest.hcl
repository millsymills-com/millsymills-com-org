mock_provider "github" {}

variables {
  org_name = "test-org"
}

run "enforcement_is_active" {
  command = plan

  assert {
    condition     = github_organization_ruleset.default_branch.enforcement == "active"
    error_message = "ruleset must be enforced, not dry-run"
  }

  assert {
    condition     = github_organization_ruleset.default_branch.target == "branch"
    error_message = "target must be branch"
  }

  assert {
    condition     = github_organization_ruleset.default_branch.rules[0].required_signatures == true
    error_message = "signed commits must be required"
  }

  assert {
    condition     = github_organization_ruleset.default_branch.rules[0].required_linear_history == true
    error_message = "linear history must be required"
  }

  assert {
    condition     = github_organization_ruleset.default_branch.rules[0].deletion == true
    error_message = "default-branch deletion must be blocked"
  }

  assert {
    condition     = github_organization_ruleset.default_branch.rules[0].non_fast_forward == true
    error_message = "force-push must be blocked"
  }
}
