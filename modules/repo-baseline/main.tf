resource "github_repository" "this" {
  name         = var.name
  description  = var.description
  visibility   = var.visibility
  topics       = var.topics
  homepage_url = var.homepage_url
  has_issues   = var.has_issues
  has_wiki     = false
  has_projects = false

  # Squash is the only merge method left on purpose. The default-branch ruleset
  # sets required_signatures, and GitHub does not sign the commits it writes for
  # a rebase-and-merge — it replays the author's commits, which it has no key
  # for. A rebase merge therefore lands unverified commits that the ruleset then
  # rejects, wedging the PR. Squash and merge-commit are both signed by GitHub;
  # merge commits are separately excluded by required_linear_history.
  delete_branch_on_merge = true
  allow_squash_merge     = true
  allow_rebase_merge     = false
  allow_merge_commit     = false

  # Grants the capability only; auto-merge is still opt-in per pull request and
  # still waits on every required check. Renovate needs it for platformAutomerge
  # (ADR-0007).
  allow_auto_merge = true

  is_template                 = var.is_template
  web_commit_signoff_required = true

  archive_on_destroy = var.archive_on_destroy

  # advanced_security omitted: GHAS is a paid Enterprise product; on Free plans
  # setting `advanced_security.status = "enabled"` is silently ignored, producing
  # perpetual plan drift. Public repos still get secret scanning, push protection,
  # and dependency review for free (see security_and_analysis below + org-baseline).
  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

# Sibling resource replaces the deprecated `vulnerability_alerts` argument
# on `github_repository` (provider 6.x). Inline removal + this resource +
# root-level `import` blocks per repo migrate state without disabling alerts.
resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}
