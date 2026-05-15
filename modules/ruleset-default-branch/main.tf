resource "github_organization_ruleset" "default_branch" {
  name        = var.ruleset_name
  target      = "branch"
  enforcement = var.enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    creation                = false
    update                  = false
    deletion                = true
    required_linear_history = true
    required_signatures     = true
    non_fast_forward        = true

    pull_request {
      # Solo-owner deadlock guard: require_code_owner_review and
      # require_last_push_approval both demand an approver who is not the PR
      # author/last pusher. CODEOWNERS in this org assigns all paths to a
      # single user, so enabling these would deadlock every owner-authored
      # PR — including the management repo's own merge-apply pipeline — with
      # no bypass path. Per-repo stricter rules (Task 16b) can layer last-push
      # approval back on for paths that actually have multiple potential
      # reviewers.
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_approving_review_count   = var.required_approving_review_count
      required_review_thread_resolution = true
    }

    dynamic "required_status_checks" {
      for_each = length(var.required_status_checks) > 0 ? [1] : []
      content {
        strict_required_status_checks_policy = true

        dynamic "required_check" {
          for_each = var.required_status_checks
          content {
            context = required_check.value
          }
        }
      }
    }
  }

  # No bypass_actors. Solo-owner shouldn't have a routine bypass path; if
  # break-glass is ever needed, temporarily set enforcement = "disabled", do
  # the work, set back to "active". The procedure (two PRs, audit trail via
  # rule-suites snapshot before+after, tracking issue) is documented in
  # docs/runbooks/ruleset-break-glass.md. Do not perform the disable locally;
  # both flips go through the normal PR + tofu-apply pipeline.
}
