# 0001. Mitigate PR-modifiable plan-gate bypass

## Status

Accepted 2026-05-15.

## Rollout status

- **Step 1** — `gate-verified.yml` landed on `main` in PR [#38](https://github.com/millsymills-com/millsymills-com-org/pull/38) on 2026-05-15. Observed posting `gate-verified` check-runs on subsequent PRs (#39, #51); this only validates the posting plumbing, not the anti-stubbing claim, which is out of scope for the assertion as implemented (see *What `gate-verified` catches and does not catch* above).
- **Step 2** — `gate-verified` added to the management-repo required-check set alongside `gate`. Tracked in issue [#34](https://github.com/millsymills-com/millsymills-com-org/issues/34). Closes the skip/rename/missing-conclusion class; the stub-with-success class remains residual and is bounded by the apply role's `job_workflow_ref @ refs/heads/main` IAM pin. Observation week begins on merge of the step-2 PR.
- **Step 3** — `gate` dropped from required checks after the observation week passes cleanly. Tracked in issue [#35](https://github.com/millsymills-com/millsymills-com-org/issues/35). Drop is safe because everything `gate` catches on its own (failure or non-skip non-success) is already caught by `gate-verified`'s `conclusion == "success"` assertion.

## Context

The `tofu-plan` workflow's `gate` job is the required-status-check on the management repo's default branch, configured in `repos_meta.tf` via `github_repository_ruleset.management_repo_checks`.

GitHub resolves a required-status-check name against the workflow files on the PR head, not against the default branch. A PR that renames or stubs the `gate` job in `.github/workflows/tofu-plan.yml` therefore produces a check of the desired shape (or no check at all). The `if: always()` synthesis in `gate` closes the "skipped == passing" loophole on `main`, but a PR can re-open it by mutating the workflow.

### Threat model

- **Mitigated independently.** AWS credential theft via this path is blocked by the IAM trust policy: apply and drift roles pin `job_workflow_ref` to `refs/heads/main`, so a tampered PR-side workflow cannot assume them.
- **Residual risk.** A bad `.tf` change merges with a stubbed gate, then gets processed by the next on-`main` `tofu apply` — which does run with apply credentials, because that run is authentically `main`. The damage surface is whatever the apply role can do in AWS + GitHub, not credential exfiltration.
- **Solo-owner posture.** The current threat model accepts this gap because closing it via CODEOWNERS-required-reviews requires a second maintainer. Recorded as a Plan-1 known limitation and in scope for Plan-2.

## Decision

Adopt the `workflow_run` pattern.

Add a main-only workflow — call it `gate-verified.yml` — triggered by `workflow_run` on completion of the workflow defined in `.github/workflows/tofu-plan.yml` (workflow `name: tofu`). Because `workflow_run` workflows are read from the default branch, a PR cannot edit them. The workflow does three things, in this order:

1. Fetches the triggering run's full job list via `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`.
2. Asserts that the job list contains a job named exactly `gate` AND its `conclusion == "success"`. A missing `gate` job, a rename, a `skipped`/`cancelled` conclusion, or a `failure` conclusion all fail the assertion.
3. Reports a check-run named `gate-verified` back to the PR head SHA — `success` if the assertion holds, `failure` otherwise.

The job inside `gate-verified.yml` is named `gate-verified` so the ruleset's required-status-check match — which compares against job name, not `"<workflow> / <job>"` — works without further qualification.

Add `gate-verified` to the management-repo ruleset's required-status-check set alongside `gate`. The existing `gate` job stays in place as the in-workflow signal that `gate-verified` reads.

### What `gate-verified` catches and does not catch

The mitigation closes the *skipped/missing/renamed* reopening of the original loophole, not all forms of PR-side `gate` mutation. Specifically:

- **Caught.** A PR that renames `gate`, deletes it, removes `if: always()` so it skips, lets `needs:` propagate a `cancelled` result, or otherwise produces a non-`success` conclusion all fail the `conclusion == "success"` assertion and block merge.
- **Not caught.** A PR that keeps a job *named* `gate` with `if: always()` but replaces its `run:` body (e.g., the validate-result/plan-result check) with a no-op that exits 0. `gate-verified` reads only job *name* and *conclusion* from the run's job list, so a same-name same-success stub satisfies the assertion. This is the residual risk paragraph above. The damage path remains: bad `.tf` change merges → `tofu apply` on `main` runs with apply credentials.

Closing the stub-with-success case requires either content-aware verification of the PR-side workflow file (e.g., compare the `tofu-plan.yml` blob between PR head and `main`, or reconstruct the gate assertion from `main` and run it on the PR's `validate`/`plan` job results) or org-level `required_workflows` paired with a stripped-down callee. Both are larger than the current additive rollout and are deferred. The IAM trust pin on `refs/heads/main` for the apply role bounds residual damage to whatever the apply role can do, not credential theft.

Rollout follows Plan-1's evaluate-then-enforce pattern: first add `gate-verified` alongside `gate` in the ruleset's required checks (both required), observe for one week, then drop `gate` from the required list in a follow-up PR.

If `gate-verified` flakes during the observation week, the rollback is symmetric: a one-line ruleset PR drops `gate-verified` from required checks and keeps `gate`. No state or workflow surgery required.

## Consequences

- A PR with legitimate workflow changes still passes the gate, because `gate-verified` reads the actual `gate`-job conclusion from the run's job list. Workflow edits that break the `gate` job (or its `needs: [validate, plan]` dependencies) correctly fail the gate.
- `workflow_run` runs in default-branch context and cannot read PR-supplied secrets. For reading a run conclusion via the GitHub API this is sufficient and preferable: it isolates the gate from anything the PR can influence.
- Two layers must stay in sync: the ruleset's required-check name and the workflow's check-run name. The ruleset definition in `repos_meta.tf` gets a comment pointing at this ADR so the coupling is visible at the call site.
- During the additive rollout week, both `gate` and `gate-verified` are required. The merge stays blocked while either check is missing, queued, in-progress, or failing — GitHub treats a not-yet-reported required check as blocking, so the `workflow_run` delay between `tofu-plan` completion and `gate-verified` posting does not create a merge window. After the week, only `gate-verified` is required.
- A PR that deletes or renames `.github/workflows/tofu-plan.yml` produces no `tofu-plan` run, so the `workflow_run` trigger never fires and `gate-verified` is never posted. The ruleset treats this as a missing required check and blocks merge. Desired behavior; worth naming explicitly.
- `gate-verified.yml` declares `permissions: checks: write` at the workflow level. `workflow_run` workflows inherit the repo's default workflow permissions, and the rest of the repo's workflows set `contents: read` only, so the new workflow must override. The `GITHUB_TOKEN` in a `workflow_run` context is scoped to the default-branch workflow yet can post check runs against the triggering PR's head SHA — this non-obvious property is what makes the mitigation work.
- One new workflow file to maintain on `main`. The plumbing is small: a `workflow_run` trigger, one API read, one check-run create.

## Alternatives considered

- **(a) CODEOWNERS on `.github/workflows/` + required reviews.** Rejected. Required-reviewer enforcement needs more than one maintainer; the same constraint already blocks `require_code_owner_review` on the default-branch ruleset. Revisit if the org gains a second maintainer.
- **(b) Extract the gate job into a reusable workflow called via `uses: org/repo/.github/workflows/gate.yml@main`.** Rejected. The caller workflow lives in the PR; a malicious PR can drop the `uses:` line or replace the calling job with a same-named stub. Same bypass class, different surface.
- **(c) Do nothing.** Rejected. The gap is an explicit Plan-1 known limitation slated for closure in Plan-2; leaving it open contradicts that plan.
- **(d) GitHub `required_workflows` (org-level).** Available on Team and Enterprise plans, and the org is on Team (verified via `gh api orgs/millsymills-com --jq '.plan'`). Rejected here for two reasons: (i) `workflow_run` is already implemented and reviewed in PR #33, so the consolidation work is pure churn; (ii) `required_workflows` runs a *separate* workflow on the PR head SHA, which still consumes PR-side actions and would require us to duplicate or restructure the existing `tofu-plan.yml` plumbing. Worth revisiting if Plan-2 adds more required org-level workflows where `required_workflows` becomes the unifying mechanism.

## References

- Issue [#13](https://github.com/millsymills-com/millsymills-com-org/issues/13) — Plan-2: mitigate PR-modifiable plan-gate bypass.
- `docs/superpowers/specs/2026-05-09-millsymills-org-design.md` — gate-bypass listed under Plan-1 known limitations.
- GitHub Actions security hardening guide, `workflow_run` section: <https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-workflow_run>.
- GitHub `required_workflows` availability (Team + Enterprise): <https://docs.github.com/en/actions/using-workflows/required-workflows>.
