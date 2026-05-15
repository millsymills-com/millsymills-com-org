# 0002. Enforce signed tag objects on `v*` refs

## Status

Proposed.

## Context

PR #17 added `.github/workflows/release.yml`, which runs `git verify-tag` against `.github/allowed_signers` on every `v*` tag push. Today this is the **belt**: a tag signed by a non-approved key (or unsigned) causes the workflow to fail after the fact, but the bad `refs/tags/v…` is already on the repo and remediation is manual — and remediation itself requires bypassing the tag-protection ruleset's `deletion = true` rule.

Issue #22 asks for the **suspenders**: make `release / verify-signed-tag` a *required* check so an unsigned or wrongly-signed `v*` tag push is *prevented* rather than merely flagged.

## What "required check on tag push" requires

For a ruleset rule to enforce signed-tag-object verification at push time, GitHub must (a) trigger the verification workflow synchronously with the tag-push event and (b) reject the ref creation if the workflow fails.

No GitHub-native ruleset mechanism does both for tag pushes, on any plan tier:

- `required_workflows` is available on Team and Enterprise (the org is on Team since the Plan-1 upgrade — verified via `gh api orgs/millsymills-com --jq '.plan'`). But `required_workflows` gates *pull-request* events; for direct refs (tag pushes have no PR) it is not invoked. ADR-0001 also notes the Team availability for the gate-bypass mitigation, where `required_workflows` is structurally applicable but was rejected for simplicity.
- `required_status_checks` on a `target = "tag"` ruleset has the wrong semantic shape. On a branch target it gates *merges*; on a tag target it can only gate *push*. The check it would gate on (`verify-signed-tag`) is emitted by a workflow whose only trigger is the very tag-push event being evaluated — so at push-evaluation time no matching `check-run` exists, and the push is either rejected unconditionally (chicken-egg) or admitted unconditionally (defeating the rule). Neither is useful.
- `required_signatures` on the tag ruleset is a near-miss: it requires the *commit the tag points to* to be signed, not the *tag object itself*. A lightweight or unsigned annotated `v*` tag pointing at a signed commit still satisfies the rule. The existing `modules/ruleset-tag-protection/main.tf` records this exact reasoning inline.

The remaining mechanisms are all *post-event*: a workflow runs after the tag lands and either accepts (audit) or rejects (auto-delete) it. Both leave a window where a bad tag is visible/clonable. The only way to get true push-time enforcement on this plan tier — or any current GitHub plan tier — is to remove the ability to push tags directly and route every tag through a default-branch workflow that gates the push itself.

## Decision

Adopt a workflow-mediated release flow and reshape the tag-protection ruleset to enforce it.

Two changes, paired:

1. **In `modules/ruleset-tag-protection`, flip `creation = false` → `creation = true`.** This blocks all direct `v*` tag pushes — including by the maintainer — leaving only ruleset bypass actors able to create new `v*` refs.

2. **Add a release workflow on `main` that builds and pushes the tag from inside GitHub Actions.** The workflow is `workflow_dispatch`-only, takes a `version` input, and runs against the commit on `main`. It does, in order:
   - Asserts the input matches `v[0-9]+\.[0-9]+\.[0-9]+` (and any extension your scheme allows).
   - Pulls the SSH **signing private key** from AWS Secrets Manager to `${RUNNER_TEMP}/release-signing-key` at `0600`, mirroring the App-PEM fetch pattern in `tofu-apply.yml`. The signing key is distinct from the writer App's PEM: the App PEM authenticates pushes; the signing key produces the tag object's SSH signature.
   - Creates a signed tag object on the workflow's `HEAD` using that key.
   - Runs `git verify-tag` against the **in-tree** `.github/allowed_signers` file as the gate — exits non-zero before pushing if verification fails. The allowed-signers list is part of the repo and reviewed via the normal PR flow; only the *private* signing key is fetched at runtime.
   - Pushes the new tag using a token tied to a bypass actor on the tag-protection ruleset (the `millsymills-org-bot-writer` GitHub App is the obvious choice; it already has `contents: write` and is wired through OIDC).
   - The existing `release.yml` (which only runs `git verify-tag` post-push) stays — it becomes a redundant audit signal on the same SHA, kept until the new flow has run cleanly at least three times.

Bypass-actor wiring: declare the writer App as a `bypass_actors` entry on the tag-protection ruleset with `bypass_mode = "always"`. The App's installation ID is already a known constant in `terraform.tfvars` / workflow secrets. No other identity can push `v*` tags.

Acceptance criteria (#22):
- A direct `git push origin v…` from a maintainer's laptop is rejected by the ruleset (`creation = true`).
- A `workflow_dispatch` run of `release.yml` (the new flow) with a valid version succeeds; a run with a tag-object signed by an unlisted key fails before the push step runs.
- The Plan-1 completed-doc bullet "Signed-tag enforcement … gate moves into a release workflow that validates tag signatures before publishing" is resolved.

## Consequences

- `creation = true` on the tag-protection ruleset is **breaking** the moment it goes from `evaluate` to `active`. Until the new workflow lands and is wired to a bypass actor, the org cannot cut a `v*` tag at all. Rollout splits into three small PRs so each step is independently reversible:
  - **PR-1 — land the new release workflow + bypass-actor wiring without changing the ruleset's `creation` rule.** `creation = false` (existing behavior) is retained; the workflow can be smoke-tested via `workflow_dispatch` and the bypass-actor block is exercised against the unchanged rule. Direct pushes still work — nothing destructive yet.
  - **PR-2 — flip `creation = false → true` with `enforcement = "evaluate"`.** Direct `git push origin v…` from a laptop now records a violation in rule-insights without rejecting; the workflow-mediated path remains the only one that bypasses cleanly. Observe for one week; a second smoke-test tag (e.g. `v0.0.0-test`) confirms the bypass-actor path still works.
  - **PR-3 — flip `enforcement = "active"`.** Direct pushes are now rejected. Sequence this PR alongside or after PR #16 if observation windows overlap, so the two ruleset flips don't compound risk.
- The release flow now executes from `main`, so the maintainer can no longer cut a tag from a feature branch. This is a deliberate consequence; it mirrors the apply-flow-only-on-main constraint already enforced for OpenTofu changes.
- Key management gets a hard dependency on the workflow's signing key. The writer App's deploy keys do not sign tag objects — that needs a dedicated SSH signing key (or sigstore/cosign equivalent) provisioned via Secrets Manager and pulled to `${RUNNER_TEMP}` at `0600`, mirroring the App-PEM pattern in `tofu-apply.yml`. If the signing key is lost, releases are blocked until a new key is added to `.github/allowed_signers`.
- The post-push `release.yml`'s value drops from "primary gate" to "audit witness." Keep it for one quarter or three runs, whichever is later, then delete.
- **Threat model — two distinct cases, only the first is accepted.**
  - *Insider — maintainer misuses the writer App.* Accepted residual. The Plan-1 spec already treats the writer App as trusted-to-the-org-admin level; if the maintainer is willing to misuse their own App they can also remove the entire ruleset. No mechanism short of multi-party authorization closes this.
  - *External — attacker exfils the App PEM or the signing key (or both) from AWS Secrets Manager / `${RUNNER_TEMP}`.* Not accepted; what compensates is keeping the two key materials separate. An attacker with only the App PEM can push but cannot produce a tag object whose signature satisfies `git verify-tag` against the in-tree `.github/allowed_signers`. An attacker with only the signing key can produce signed tag objects but cannot push them past `creation = true` without the App-authenticated push step. The bypass becomes meaningfully harder than a single-key compromise; this is the load-bearing reason for distinct keys.
- Provider validation: `creation = true` on `target = "tag"` is supported (the `creation`/`update`/`deletion` triple is documented under "Rules Configuration" as target-agnostic). No provider change needed.

## Alternatives considered

- **(a) `required_workflows` on the tag ruleset.** Available on Team (the current plan) and Enterprise. Rejected on structural grounds: `required_workflows` gates pull-request events and does not apply to direct tag pushes, which have no PR. Even if the API admitted a tag target, the gating workflow is post-event and could only audit, not prevent. Documented here so a future maintainer doesn't reopen the question after a plan-tier review.
- **(b) `required_status_checks` on the tag ruleset.** Semantically broken as analyzed above — the only workflow that produces the gating check is itself triggered by the push being gated. Rejected.
- **(c) Status quo + auto-cleanup bot.** Leave `creation = false`, keep post-push `release.yml`, add a bot that deletes (via the writer App, which can bypass `deletion = true`) tags whose `verify-signed-tag` fails. Cheaper but leaves a window where a bad tag is visible/clonable; loses the "prevented at push" property #22 explicitly requires. Rejected as primary; recorded as a fallback.
- **(d) Do nothing.** Rejected — the Plan-1 deferred-item list and the issue both call for closure.
- **(e) Status quo: direct laptop push of a signed tag + post-push verification.** This is exactly the mechanism PR #17 ships today: the maintainer signs locally with a key whose public part is in `.github/allowed_signers`, pushes `v*` directly, and a workflow then runs `git verify-tag` and fails the run if the signature is unacceptable. Rejected as the long-term answer for two reasons. (i) No push-time gate — a bad tag still lands on the repo and requires manual deletion, which itself requires bypassing the `deletion = true` rule. (ii) `creation = false` means any write-access principal can create a `v*` ref, signed or not; the audit-only workflow doesn't change who can push, only what gets surfaced after. Worth recording explicitly because it is the *current* state and reopening "why aren't we just keeping this?" is the obvious follow-up question.
- **(f) PR-based release (tag-as-content).** A `TAGS` file under branch protection, with releases triggered by merging an update. Inherits all branch protections automatically. Rejected because it breaks every standard release tool that expects to push `git tag`, requires a translator workflow to turn the file content into actual refs, and introduces a second coupling between branch and tag state that drifts on rollback.

## References

- Issue [#22](https://github.com/millsymills-com/millsymills-com-org/issues/22) — Plan-2: make release-tag verification a required check for `v*` refs.
- PR [#17](https://github.com/millsymills-com/millsymills-com-org/pull/17) — the post-push `release` workflow.
- ADR [0001](./0001-gate-bypass-mitigation.md) — documents `required_workflows` availability on Team (verified) and why it was not the chosen mechanism for the gate-bypass mitigation.
- `modules/ruleset-tag-protection/main.tf` — inline note explaining why `required_signatures` does not cover tag objects.
- `docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md` — "Signed-tag enforcement" under deliberately-deferred.
