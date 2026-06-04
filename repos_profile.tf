# The org profile repo. GitHub renders `profile/README.md` from a public repo
# named `.github` at the top of the org page. tofu owns the repo *shell* only;
# the README content lands via a normal PR on the `.github` repo itself (the org
# default-branch ruleset applies here too, so content is PR-gated like every
# other repo). `auto_init = true` gives it a default branch at creation so that
# first content PR has a base to target.
module "org_profile_repo" {
  source = "./modules/repo-baseline"

  name         = ".github"
  description  = "Org profile."
  visibility   = "public"
  homepage_url = "https://millsymills.com"
  has_issues   = false
  topics       = []
  is_template  = false
  auto_init    = true
}
