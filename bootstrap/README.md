# bootstrap

One-time setup for the millsymills-com-org Tofu pipeline.

## Order of operations

1. `./aws-bootstrap.sh` — creates AWS state infrastructure (S3, KMS, IAM, Secrets Manager).
2. Follow `github-bootstrap.md` to create the two GitHub Apps and customize OIDC subject template.
3. Run `tofu init` and `tofu import` (see top-level docs).
4. Verify CI works end-to-end.
5. Touch `bootstrap/.disabled` (or commit it as part of the final bootstrap commit) to lock further runs.

## Files

- `aws-bootstrap.sh` — idempotent AWS provisioning script.
- `lib/_common.sh` — shared helpers.
- `tests/` — bats tests.
- `aws-output.json` — committed; non-secret ARNs and IDs.
- `github-bootstrap.md` — manual GitHub App creation runbook.
- `github-output.json` — committed; non-secret App IDs and Installation IDs.
- `.disabled` — sentinel file; if present, scripts refuse to run unless `--force`.

## Forbidden after bootstrap

After `bootstrap/.disabled` is committed, no manual `tofu apply` from any developer machine.
All changes go through PR → CI plan → merge → CI apply.

## Re-arming for a deliberate re-run

The seal pattern (`bootstrap/.disabled`) is a soft block: `aws-bootstrap.sh` refuses to run while the sentinel exists, but the operator can re-enable it. Re-running is destructive-adjacent — the script recreates IAM roles, rotates Secrets Manager entries, and republishes the OIDC trust shape — so this should never happen as part of a routine change. The only legitimate triggers are: a key compromise requiring credential rotation, an AWS-region migration, or a regression in the bootstrap layer itself that cannot be fixed in tofu.

### Known drift to fix before re-running

Two divergences between what is currently committed in `bootstrap/` and what is live in production have not been backported to the script. Re-running without addressing them would silently re-introduce the broken state.

1. **`github-bootstrap.md` records `organization_administration: read` for the reader App.** The live reader App was bumped to `organization_administration: write` via the GitHub UI during Plan-1 because `GET /orgs/{org}/rulesets/{id}` silently requires `:write` (verified empirically in PR canary). If the App is recreated from the runbook as-is, `tofu plan` will fail on every ruleset refresh until the scope is bumped manually. **Before re-running**: update the runbook's App creation step to set `organization_administration: write` from the start.
2. **`aws-bootstrap.sh` emits a `repository_owner_id` condition in the OIDC trust policies.** The trust policies on the live IAM roles (`gha-millsymills-org-tofu-{plan,apply,drift}`) were updated via `aws iam update-assume-role-policy` to drop that condition because GitHub's OIDC provider silently rejects it on this account (verified via in-workflow `aws sts assume-role-with-web-identity` debug call). The currently-live trust shape uses `aud + sub + repository_id + environment + job_workflow_ref`, **without** `repository_owner_id`. If `aws-bootstrap.sh` is re-run as-is, it will re-introduce the broken condition and break credential issuance. **Before re-running**: patch the script's trust-policy heredoc to match the currently-live shape (the live shape is reflected in the `gha-millsymills-org-tofu-*` IAM roles' assume-role-policy documents and can be exported via `aws iam get-role`).

Both items are also recorded in `docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md` under known limitations, and in the project's CLAUDE.md.

### Procedure

1. Open an issue describing the trigger for the re-run (compromise, region migration, regression). Link it from PR descriptions for the changes below.
2. Land a PR that backports the known-drift fixes above into `bootstrap/github-bootstrap.md` and `bootstrap/aws-bootstrap.sh`. Merging this PR alone changes nothing live — the script is still sealed.
3. In a second PR, remove `bootstrap/.disabled` (or rename it to `.disabled.archived-<date>`). This PR is the re-arming gate; review it carefully. Merging it makes the script runnable, but `aws-bootstrap.sh --force` is still required for a non-trivial re-run; `--force` is needed both for the seal-aware logic and to acknowledge the destructive nature of the script.
4. Execute the re-run locally with `--force`. Capture stdout + stderr to a transcript file. Do not skip the bats tests in `bootstrap/tests/` after; they exercise the seal-guard and the idempotency expectations.
5. Verify in the AWS console (or via `aws iam get-role`) that the live trust policies still match the expected shape — the re-run script's idempotency guarantees may or may not preserve manual fixes applied since the previous run, depending on the resource.
6. Land a third PR that re-creates `bootstrap/.disabled` with the new completion timestamp, commit SHA, and operator name (mirror the existing sentinel's format — see the current file for the schema). Merging this PR re-seals the bootstrap layer.
7. Update the project's CLAUDE.md (`Operational guardrails` section) only if the trigger introduced new known-drift items.

The three-PR shape is deliberate: it forces explicit review at the points where the system goes from "sealed" to "runnable" and back. Bundling them would let the seal lift and re-set in a single merge with no opportunity to spot an unintended change between the two states.

### If a re-run leaves the bootstrap drifted

If a re-run completes but `tofu plan` or workflow CI shows new drift afterward (the script's idempotency claims are not perfect), the resolution path is the normal one: a PR that brings the tofu code into agreement with the live state. Do not re-run the script a second time to "fix it" — running again only adds variance.
