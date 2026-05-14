# 0001. Mitigate PR-modifiable plan-gate bypass

## Status

Proposed.

## Context

The `tofu-plan` workflow's `gate` job is the required-status-check on the management repo's default branch, configured in `repos_meta.tf` via `github_repository_ruleset.management_repo_checks`.

GitHub resolves a required-status-check name against the workflow files on the PR head, not against the default branch. A PR that renames or stubs the `gate` job in `.github/workflows/tofu-plan.yml` therefore produces a check of the desired shape (or no check at all). The `if: always()` synthesis in `gate` closes the "skipped == passing" loophole on `main`, but a PR can re-open it by mutating the workflow.

AWS credential theft via this path is independently mitigated: the IAM trust policy pins `job_workflow_ref` to `refs/heads/main` on apply and drift roles. The residual risk is a bad `.tf` change merging with a stubbed gate, then being processed by the next on-`main` apply.

The solo-owner threat model currently accepts this gap. It is recorded as a Plan-1 known limitation and is in scope for Plan-2.

## Decision

Adopt the `workflow_run` pattern.

Add a main-only workflow — call it `gate-verified.yml` — triggered by `workflow_run` on completion of `tofu-plan.yml`. Because `workflow_run` workflows are read from the default branch, a PR cannot edit them. The workflow fetches the triggering run's conclusion via the GitHub API, asserts `conclusion == "success"`, and reports a check named `gate-verified` back to the PR head SHA.

Rename the ruleset's required-status-check from `gate` to `gate-verified`. The existing `gate` job stays in place as defense-in-depth; it still catches naive bypass attempts and remains useful as the in-workflow signal that produces the conclusion `gate-verified` reads.

Rollout follows Plan-1's evaluate-then-enforce pattern: first add `gate-verified` to the ruleset's required checks alongside `gate` (additive, both required), observe for one week, then drop `gate` from the required list in a follow-up PR.

## Consequences

- A PR with legitimate workflow changes still passes the gate, because `gate-verified` reads the actual run conclusion. Workflow edits that break the plan job correctly fail the gate.
- `workflow_run` runs in default-branch context and cannot read PR-supplied secrets. For reading a run conclusion via the GitHub API this is sufficient and preferable: it isolates the gate from anything the PR can influence.
- Two layers must stay in sync: the ruleset's required-check name and the workflow's check-run name. The ruleset definition in `repos_meta.tf` gets a comment pointing at this ADR so the coupling is visible at the call site.
- During the additive rollout week, both `gate` and `gate-verified` are required. The merge stays blocked while either check is missing, queued, in-progress, or failing — GitHub treats a not-yet-reported required check as blocking, so the `workflow_run` delay between `tofu-plan` completion and `gate-verified` posting does not create a merge window. After the week, only `gate-verified` is required.
- A PR that deletes or renames `.github/workflows/tofu-plan.yml` produces no `tofu-plan` run, so the `workflow_run` trigger never fires and `gate-verified` is never posted. The ruleset treats this as a missing required check and blocks merge. Desired behavior; worth naming explicitly.
- `gate-verified.yml` declares `permissions: checks: write` at the workflow level. `workflow_run` workflows inherit the repo's default workflow permissions, and the rest of the repo's workflows set `contents: read` only, so the new workflow must override. The `GITHUB_TOKEN` in a `workflow_run` context is scoped to the default-branch workflow yet can post check runs against the triggering PR's head SHA — this non-obvious property is what makes the mitigation work.
- One new workflow file to maintain on `main`. The plumbing is small: a `workflow_run` trigger, one API read, one check-run create.

## Alternatives considered

- **(a) CODEOWNERS on `.github/workflows/` + required reviews.** Rejected. Required-reviewer enforcement needs more than one maintainer; the same constraint already blocks `require_code_owner_review` on the default-branch ruleset. Revisit if the org gains a second maintainer.
- **(b) Do nothing.** Rejected. The gap is an explicit Plan-1 known limitation slated for closure in Plan-2; leaving it open contradicts that plan.
- **(c) GitHub Enterprise "required workflows".** Not applicable. The org is on the Free plan; required workflows are an Enterprise feature.

## References

- Issue [#13](https://github.com/millsymills-com/millsymills-com-org/issues/13) — Plan-2: mitigate PR-modifiable plan-gate bypass.
- `docs/superpowers/specs/2026-05-09-millsymills-org-design.md` — gate-bypass listed under Plan-1 known limitations.
- GitHub Actions security hardening guide, `workflow_run` section: <https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-workflow_run>.
