# ruleset-tag-protection

Blocks force-update and deletion of `v*` tags org-wide. Codifies the
"tag-protection" ruleset in the spec.

## Signed tags — known gap

`required_signatures` is intentionally NOT set on this ruleset. GitHub's
ruleset API enforces signatures on the *commit* a ref points to, not on
the tag object itself; a lightweight or unsigned annotated tag pointing at
a signed commit would still satisfy the rule. To get true signed-release-tag
guarantees, the release workflow must verify `git tag -v` (or equivalent)
before publishing. That check is a Plan-2 follow-up; until then this module
only enforces tag *immutability*, not tag *provenance*.
