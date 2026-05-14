import {
  to = module.management_repo.github_repository.this
  id = "millsymills-com-org"
}

import {
  to = module.management_repo.github_repository_vulnerability_alerts.this
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

# Required-status-checks ruleset on the management repo's default branch.
#
# Context strings are bare JOB names, not the "<workflow> / <job>" form the
# PR UI renders. GitHub's check-runs API returns just the job name, and that
# is what the ruleset matcher compares against — verified empirically:
#
#   $ gh api repos/millsymills-com/millsymills-com-org/commits/<SHA>/check-runs \
#       --jq '.check_runs[].name' | sort -u
#   actionlint
#   analyze (actions)
#   CodeQL
#   gate
#   gitleaks
#   plan
#   validate
#   zizmor
#
# Confirmed against the head commits of PRs #14 (c6e82c9) and #17 (5e04911)
# on 2026-05-14. Plan-1 v5 spec specified "<workflow> / <job>"; the empirical
# pivot is intentional. If a workflow's job `name:` changes, the matching
# `context = "…"` here must change in lockstep.
resource "github_repository_ruleset" "management_repo_checks" {
  name        = "management-repo-checks"
  repository  = module.management_repo.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    required_status_checks {
      strict_required_status_checks_policy = true

      # `gate` is the synthesizer job in tofu-plan.yml (`if: always()`) that
      # depends on validate + plan and asserts the conditional rule:
      #   - validate must succeed (every PR)
      #   - plan must succeed (internal PR) or be skipped (fork PR)
      # Encoding it as a single context avoids the "skipped == passing"
      # loophole that would otherwise let fork PRs merge.
      required_check { context = "gate" }
      required_check { context = "zizmor" }
      required_check { context = "gitleaks" }
      required_check { context = "actionlint" }
      required_check { context = "analyze (actions)" }
    }
  }
}
