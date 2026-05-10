# org-baseline

Codifies organization-wide security settings for `millsymills-com`. These settings
correspond directly to the "Org-wide settings" subsection of the spec
(`docs/superpowers/specs/2026-05-09-millsymills-org-design.md`).

## What this enforces

- Members cannot create, delete, change visibility, or fork private repos.
- Outside collaborators cannot be invited by non-owners.
- Default permission for outside collaborators is `none`.
- Web-UI commits must be signed off.
- Org projects (classic) and repo projects are disabled.
- Dependabot alerts, Dependabot security updates, dependency graph, secret scanning,
  push protection, and advanced security default-on for every new repo.

## Inputs

See `variables.tf`.

## Outputs

- `org_name` — passes through the org slug for downstream wiring.

## Tests

The tests run from the **project root**, not from inside the module. The module
takes its inputs from the `module "org_baseline"` call in the root `org.tf`, so
the test file does not declare its own `variables {}` block.

```sh
tofu test -test-directory=modules/org-baseline/tests
```

Assertions are plan-time only, with the github provider mocked
(`mock_provider "github"`) — no real API calls are made.
