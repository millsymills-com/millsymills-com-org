module "org_baseline" {
  source = "./modules/org-baseline"

  org_name      = var.org_name
  billing_email = "mills@millsymills.com"
  display_name  = "millsymills.com"
}

module "ruleset_default_branch" {
  source = "./modules/ruleset-default-branch"

  # Initial rollout: evaluate-mode (dry-run; logs violations without blocking).
  # Flip to "active" in a follow-up commit after one full week of observing
  # the org's rule-insights logs for false positives. Drop this argument to
  # take the module default ("active").
  enforcement = "evaluate"
  # No required_status_checks here. The org-wide ruleset applies to ALL repos,
  # most of which won't run tofu/codeql/etc. workflows. Per-repo required checks
  # for the management repo are configured in repos_meta.tf (Task 16a/16b).
  required_status_checks          = []
  required_approving_review_count = 0 # solo-dev caveat (spec Section 4)
}

module "ruleset_tag_protection" {
  source = "./modules/ruleset-tag-protection"

  # Mirrors the branch-protection rollout: evaluate-mode for the initial
  # apply, flip to "active" in a follow-up commit once we've watched for a
  # week of rule-insights data and exercised the release flow at least once.
  enforcement = "evaluate"
}
