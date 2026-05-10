plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# tflint-ruleset-github is not an official plugin (no equivalent exists for the
# integrations/github provider). github_repository / github_organization rules
# are covered by manual review and provider-side validation.

plugin "aws" {
  enabled = true
  version = "0.36.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  format           = "compact"
  call_module_type = "all"
}
