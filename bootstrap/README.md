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
