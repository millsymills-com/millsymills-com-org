# millsymills-com-org

OpenTofu configuration for the `millsymills-com` GitHub organization: organization settings, repository settings, and branch and tag rulesets, including this management repository itself.

## What is here

| Component | Source |
| --- | --- |
| Organization settings and ruleset composition | [`org.tf`](org.tf), [`modules/`](modules/) |
| Existing repository settings | [`repos_existing.tf`](repos_existing.tf) |
| This repository, its environments, and required checks | [`repos_meta.tf`](repos_meta.tf) |
| Organization profile repository settings | [`repos_profile.tf`](repos_profile.tf) |
| AWS state backend and GitHub provider authentication | [`backend.tf`](backend.tf), [`providers.tf`](providers.tf) |
| One-time provisioning and its disabled guard | [`bootstrap/`](bootstrap/) |

Repository content is maintained in each project's own pull requests. This configuration does not establish that every repository has identical CI coverage or that every GitHub setting is provider-managed. [`scripts/set-extra-org-settings.sh`](scripts/set-extra-org-settings.sh) documents settings outside the provider's coverage.

## Architecture and change flow

GitHub Actions assumes AWS roles through OIDC. State uses S3 with KMS encryption and native locking; GitHub App private keys are retrieved from Secrets Manager at workflow runtime. Plan and apply use separate App identities. The plan identity is not strictly read-only: the documented org-ruleset refresh requires organization-administration write permission. See the [bootstrap completion notes](docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md) for this limitation and the deviations from the original design.

1. A pull request runs [static validation](.github/workflows/tofu-plan.yml). Internal PRs also run a credentialed plan; fork PRs skip that job.
2. The `gate` job checks the expected validation/plan results. [`gate-verified`](.github/workflows/gate-verified.yml) runs from the default branch and checks the gate result and plan-workflow integrity. Its boundaries and the maintainer-controlled `workflow-update` exception are documented in [ADR-0001](docs/adr/0001-gate-bypass-mitigation.md).
3. After review and required checks, merging configuration changes to `main` triggers [`tofu-apply`](.github/workflows/tofu-apply.yml), which creates a fresh plan before applying. The workflow has path filters; a README-only merge does not trigger an apply.
4. [`tofu-drift`](.github/workflows/tofu-drift.yml) is scheduled daily at 07:00 UTC and can be dispatched manually to report drift.

Do not run a local `tofu apply`, re-enable bootstrap, or change ruleset enforcement as part of routine validation. Plans and state can contain sensitive information; do not commit them or credentials.

## Validate a checkout

Use the versions in [`.tool-versions`](.tool-versions): OpenTofu 1.10.3, TFLint 0.55.1, ShellCheck 0.10.0, and Bats 1.11.1. Git and a shell are also required. These checks do not need AWS or GitHub administrative credentials.

### Offline formatting

With OpenTofu already installed:

```sh
tofu fmt -check -recursive
```

### Static validation and mocked tests

Initialization downloads providers or plugins, so this is not an offline check on a fresh checkout. `-backend=false` avoids initializing the live state backend; no live infrastructure plan or apply is run.

```sh
tofu init -backend=false -input=false
tofu validate
tflint --init
tflint --recursive --format=compact

for module in org-baseline repo-baseline ruleset-default-branch ruleset-tag-protection; do
  tofu -chdir="modules/$module" init -backend=false -input=false
  tofu -chdir="modules/$module" test
done

bats bootstrap/tests/test_disabled_guard.bats
```

The module tests use mocked providers. Run them from each module as above: a root-level `tofu test` does not discover the module test suites. The Bats command tests the disabled guard in temporary copies using dry-run mode; it does not provision resources. The broader bootstrap test suite includes pre-sealing assumptions, so it is not presented here as a post-bootstrap validation command.

The [pre-commit configuration](.pre-commit-config.yaml) and [workflow files](.github/workflows/) define additional lint and security checks. A credentialed plan is a separate operational step, normally performed by PR CI, not part of the commands above.

## Implemented and planned

The [Plan-1 completion record](docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md) documents the original deployment and verification. It is historical evidence, not a claim that today's hosted checks are green. Current configuration and workflow runs are the source for present behavior.

- Bootstrap is sealed by [`bootstrap/.disabled`](bootstrap/.disabled).
- The current [`release`](.github/workflows/release.yml) workflow verifies approved SSH tag signatures **after** a `v*` tag is pushed. It does not prevent an unsigned tag from first appearing. Workflow-mediated, pre-push signature enforcement is the accepted design in [ADR-0002](docs/adr/0002-required-signed-tag-check.md), with implementation tracked in [#36](https://github.com/millsymills-com/millsymills-com-org/issues/36).
- The broader [portfolio-content spec](docs/superpowers/specs/2026-05-14-millsymills-portfolio-content.md) is planning material. Its implementation plan is tracked in [#48](https://github.com/millsymills-com/millsymills-com-org/issues/48); it should not be read as a list of shipped projects or controls.

## Operational references

- [Ruleset break-glass procedure](docs/runbooks/ruleset-break-glass.md)
- [Signing-key rotation procedure](docs/runbooks/signing-key-rotation.md)
- [Security reporting policy](SECURITY.md)
- [Original design and rationale](docs/superpowers/specs/2026-05-09-millsymills-org-design.md)

## Licensing

No license has been declared in this repository. The maintainer's choice is tracked in [#96](https://github.com/millsymills-com/millsymills-com-org/issues/96); this README does not grant additional reuse rights or infer a license from sibling projects.
