mock_provider "github" {}

run "tag_immutability_enforced" {
  command = plan

  assert {
    condition     = github_organization_ruleset.tag_protection.target == "tag"
    error_message = "target must be tag"
  }

  assert {
    condition     = github_organization_ruleset.tag_protection.enforcement == "active"
    error_message = "tag protection must be enforced by default"
  }

  assert {
    condition     = github_organization_ruleset.tag_protection.rules[0].update == true
    error_message = "tag updates must be blocked"
  }

  assert {
    condition     = github_organization_ruleset.tag_protection.rules[0].deletion == true
    error_message = "tag deletion must be blocked"
  }

  assert {
    condition     = github_organization_ruleset.tag_protection.conditions[0].ref_name[0].include[0] == "refs/tags/v*"
    error_message = "default tag pattern must be v*"
  }
}
