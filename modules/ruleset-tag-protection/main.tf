resource "github_organization_ruleset" "tag_protection" {
  name        = var.ruleset_name
  target      = "tag"
  enforcement = var.enforcement

  conditions {
    ref_name {
      include = ["refs/tags/${var.tag_pattern}"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  # Provider semantics: creation/update/deletion = true means the action is
  # BLOCKED by the rule. creation=false allows new tags; update=true and
  # deletion=true together make tags immutable once pushed.
  #
  # `required_signatures` is deliberately omitted. GitHub's ruleset API
  # enforces signatures on the *commit* the ref points to, not on the tag
  # object itself, so a lightweight or unsigned annotated `v*` tag pointing
  # at a signed commit would still satisfy the rule. Signed-tag-object
  # enforcement belongs in the release workflow (verify `git tag -v` before
  # publishing) — tracked as a follow-up.
  rules {
    creation = false
    update   = true
    deletion = true
  }
}
