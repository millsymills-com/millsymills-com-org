# Org profile facelift — recruiter-facing polish

Status: Draft — 2026-06-04
Author: Andrew Mills

## Goal

Make the `millsymills-com` GitHub org presentable to prospective recruiters. The
public surface today is bare: no org description, website, or location; no org
profile README; two repos missing topics; one repo with latent destructive
drift. Positioning: a **security engineer who builds MCP tooling and treats
infrastructure / supply-chain as code**.

## Constraints

- **Identity boundary.** Real name "Andrew Mills" may appear. The employer is
  **never** named or hinted at in any public artifact. General location and a
  contact link are allowed.
- **Org-as-code.** Every settable surface flows through `tofu plan` → PR →
  merge → `tofu apply`. No direct API writes to tofu-managed settings.
- **Active rulesets.** The org default-branch ruleset is `active`, targets
  `~ALL` repos / `~DEFAULT_BRANCH`, and requires a pull request + signed
  commits. Tofu therefore cannot commit a file directly to a new repo's default
  branch.
- **No ruleset weakening.** The security posture is itself part of the
  recruiter story; the facelift must not carve holes in it.

## Scope

### 1. Org metadata — `modules/org-baseline` + `org.tf`

Add three optional inputs to `org-baseline`, wired onto
`github_organization_settings` (provider `integrations/github ~> 6.4` supports
all three):

| field | value |
|-------|-------|
| `description` | `MCP servers and security-hardened org-as-code. Built by Andrew Mills.` |
| `blog` | `https://millsymills.com` |
| `location` | `Pacific Northwest — Remote` |

New variables default to `""` so existing module callers and tests are
unaffected; `org.tf` passes the values above.

### 2. Org profile README — new `.github` repo (two-phase)

GitHub renders `profile/README.md` from a public `.github` repo at the top of
the org page.

**Phase A (this management repo, tofu):** declare a public `.github` repo via
the `repo-baseline` module — description `Org profile.`, no topics, issues off,
not a template. Settings only; **no content**. The org default-branch ruleset
applies to it automatically (no exclusion).

**Phase B (the `.github` repo, after it exists):** add `profile/README.md` via
an ordinary PR on `.github` and self-merge (the default-branch ruleset requires
a PR but `required_approving_review_count = 0`, so a solo owner does not
deadlock). README content is intentionally **not** tofu-managed — marketing
copy does not belong in the apply cycle, and this avoids any ruleset carve-out.

**README structure** (lead: security + AI tooling):

1. Title + one-line tagline.
2. Short intro — Andrew Mills, security engineer building MCP tooling and
   managing infrastructure as code. No employer.
3. **MCP servers** — grouped list, one line each (unraid, unifi, gandi,
   protonmail, flipperzero, shortcut).
4. **Infrastructure** — the `millsymills-com-org` org-as-code repo.
5. **Engineering practices** — the differentiator: OIDC-only CI (no static
   cloud keys), SHA-pinned actions, signed release tags, supply-chain scanning
   (gitleaks / zizmor / CodeQL / Scorecard), PR-gated apply. Factual, no
   superlatives.
6. **Contact** — `https://millsymills.com` and `mills@millsymills.com`.

Tasteful tech tags (Go, Python, OpenTofu) only if they stay subtle; no badge
soup.

### 3. Repo polish — `repos_existing.tf`

- `shortcut-mcp` — add topics: `mcp`, `mcp-server`, `model-context-protocol`,
  `python`, `fastmcp`, `shortcut`, `project-management`, `rest-api`.
- `flipperzero-mcp` — add topics: `mcp`, `mcp-server`,
  `model-context-protocol`, `python`, `flipper-zero`, `protobuf`, `usb`,
  `rpc`, `hardware`.
- `unifi-mcp` — populate description and topics in tofu to **match live**:
  description `MCP server for UniFi Network, Protect, and Site Manager APIs. 82
  tools, readonly by default with explicitly gated writes.`; topics `fastmcp`,
  `mcp`, `model-context-protocol`, `python`, `ubiquiti`, `unifi`,
  `unifi-network`, `unifi-protect`.

**Latent bug fixed here:** `unifi-mcp` currently has `description = ""` and
`topics = []` in tofu while the live repo is populated. The next `tofu apply`
would silently wipe both. Bringing tofu in line with live closes that.

### 4. Pinned repos — manual (UI-only), documented

Org pinned repositories have no REST/GraphQL/Terraform surface, like the four
existing web-UI-only org settings. Document the action and the recommended pin
set in `scripts/` (mirroring `set-extra-org-settings.sh`'s read-and-flag
pattern where possible) or in the org-profile docs. Recommended six pins, in
order: `millsymills-com-org`, `unraid-mcp`, `unifi-mcp`, `gandi-mcp`,
`protonmail-mcp`, `flipperzero-mcp`.

## Out of scope

- Profile picture (owner is sourcing it).
- Per-repo README rewrites in the individual MCP repos.
- Any change to rulesets, OIDC trust, or the CI pipeline.

## Delivery

- **PR 1** (this repo, branch `org-profile-facelift`): spec doc, org metadata,
  `.github` repo declaration, repo-polish edits. Goes through the normal
  `gate` / `gate-verified` plan flow. Merge → apply creates the `.github` repo
  and applies metadata + topics.
- **PR 2** (the new `.github` repo, after PR 1 applies): `profile/README.md`.
- **Manual:** owner sets the six pinned repos and uploads the profile picture
  via the org UI.

## Testing / verification

- `tofu fmt -check -recursive`, `tofu validate`, `tflint --recursive`.
- `tofu test` — extend `modules/org-baseline/tests` to assert the three new
  settings render; mock_provider, no API calls.
- `actionlint` / `zizmor` unaffected (no workflow changes).
- Post-apply: `gh api orgs/millsymills-com` shows description/blog/location;
  `gh repo view millsymills-com/.github` exists; topics present on
  `shortcut-mcp` / `flipperzero-mcp` / `unifi-mcp`.
