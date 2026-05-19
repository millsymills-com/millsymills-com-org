module "org_baseline" {
  source = "./modules/org-baseline"

  org_name      = var.org_name
  billing_email = "mills@millsymills.com"
  display_name  = "millsymills.com"
}

module "ruleset_default_branch" {
  source = "./modules/ruleset-default-branch"

  # No required_status_checks here. The org-wide ruleset applies to ALL repos,
  # most of which won't run tofu/codeql/etc. workflows. Per-repo required checks
  # for the management repo are configured in repos_meta.tf (Task 16a/16b).
  required_status_checks          = []
  required_approving_review_count = 0 # solo-dev caveat (spec Section 4)
}

module "ruleset_tag_protection" {
  source = "./modules/ruleset-tag-protection"
}
