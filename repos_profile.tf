# The org profile repo. GitHub renders `profile/README.md` from a public repo
# named `.github` at the top of the org page. tofu owns the repo *shell* only;
# the README content lands via a normal PR on the `.github` repo itself.
#
# Imported, not created: the integrations/github provider's repo-create path
# issues a follow-up PATCH that sets web_commit_signoff_required, which an org
# enforcing commit signoff rejects with 422. Every other repo here is likewise
# adopted by import (see repos_existing.tf / repos_meta.tf); `.github` was
# created out-of-band with a default branch and is adopted the same way.
import {
  to = module.org_profile_repo.github_repository.this
  id = ".github"
}

module "org_profile_repo" {
  source = "./modules/repo-baseline"

  name         = ".github"
  description  = "Org profile."
  visibility   = "public"
  homepage_url = "https://millsymills.com"
  has_issues   = false
  topics       = []
  is_template  = false
}
