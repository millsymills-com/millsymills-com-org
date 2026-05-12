import {
  to = module.management_repo.github_repository.this
  id = "millsymills-com-org"
}

module "management_repo" {
  source = "./modules/repo-baseline"

  name         = "millsymills-com-org"
  description  = "Org-as-code for millsymills-com. PR-driven, OIDC-enforced."
  visibility   = "public"
  topics       = ["governance", "iac", "opentofu", "supply-chain", "security"]
  homepage_url = "https://github.com/millsymills-com"
}

# Per-repo required-status-checks ruleset is intentionally deferred to Task 16b
# (after Task 24 + first verified CI run). Adding it here would block every PR
# because the required check contexts wouldn't yet exist in GitHub's history.

resource "github_repository_environment" "tofu_plan" {
  repository  = module.management_repo.name
  environment = "tofu-plan"
  # No deployment_branch_policy: plan workflow must auto-run on every PR
  # branch (spec Section 5). The AWS IAM role's `job_workflow_ref @ refs/heads/main`
  # condition + `sub` pin to `environment:tofu-plan` constrain credential issuance.
}

resource "github_repository_environment" "tofu_apply" {
  repository  = module.management_repo.name
  environment = "tofu-apply"

  # Belt + suspenders on top of the IAM `job_workflow_ref` pin: only the
  # `main` branch may target this environment.
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "tofu_apply_main" {
  repository     = module.management_repo.name
  environment    = github_repository_environment.tofu_apply.environment
  branch_pattern = "main"
}

resource "github_repository_environment" "tofu_drift" {
  repository  = module.management_repo.name
  environment = "tofu-drift"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "tofu_drift_main" {
  repository     = module.management_repo.name
  environment    = github_repository_environment.tofu_drift.environment
  branch_pattern = "main"
}
