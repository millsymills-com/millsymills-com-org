resource "github_repository" "this" {
  name         = var.name
  description  = var.description
  visibility   = var.visibility
  topics       = var.topics
  homepage_url = var.homepage_url
  has_issues   = var.has_issues
  has_wiki     = false
  has_projects = false

  delete_branch_on_merge = true
  allow_squash_merge     = true
  allow_rebase_merge     = true
  allow_merge_commit     = false
  allow_auto_merge       = false

  is_template                 = var.is_template
  vulnerability_alerts        = true
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
