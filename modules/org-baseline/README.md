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

`tofu test -test-directory=tests` exercises the resource attributes via plan-time
assertions; no real API calls are made (mocked at provider level).
