# 0002. Enforce signed tag objects on `v*` refs

## Status

Proposed.

## Context

PR #17 added `.github/workflows/release.yml`, which runs `git verify-tag` against `.github/allowed_signers` on every `v*` tag push. Today this is the **belt**: a tag signed by a non-approved key (or unsigned) causes the workflow to fail after the fact, but the bad `refs/tags/v…` is already on the repo and remediation is manual — and remediation itself requires bypassing the tag-protection ruleset's `deletion = true` rule.

Issue #22 asks for the **suspenders**: make `release / verify-signed-tag` a *required* check so an unsigned or wrongly-signed `v*` tag push is *prevented* rather than merely flagged.

## What "required check on tag push" requires

For a ruleset rule to enforce signed-tag-object verification at push time, GitHub must (a) trigger the verification workflow synchronously with the tag-push event and (b) reject the ref creation if the workflow fails. The only ruleset mechanism that has both properties is `required_workflows`.

ADR-0001 already established that `required_workflows` is gated to GitHub Enterprise plans (option (c) in its alternatives). `millsymills-com` is on the Free plan, so `required_workflows` is not available.

The other candidate, `required_status_checks` on a `target = "tag"` ruleset, has the wrong semantic shape. On a branch target it gates *merges*; on a tag target it can only gate *push*. The check it would gate on (`verify-signed-tag`) is emitted by a workflow whose only trigger is the very tag-push event being evaluated — so at push-evaluation time no matching `check-run` exists, and the push is either rejected unconditionally (chicken-egg) or admitted unconditionally (defeating the rule). Neither is useful.

`required_signatures` on the tag ruleset is a near-miss: it requires the *commit the tag points to* to be signed, not the *tag object itself*. A lightweight or unsigned annotated `v*` tag pointing at a signed commit still satisfies the rule. The existing `modules/ruleset-tag-protection/main.tf` records this exact reasoning inline.

## Decision

Adopt a workflow-mediated release flow and reshape the tag-protection ruleset to enforce it.

Two changes, paired:

1. **In `modules/ruleset-tag-protection`, flip `creation = false` → `creation = true`.** This blocks all direct `v*` tag pushes — including by the maintainer — leaving only ruleset bypass actors able to create new `v*` refs.

2. **Add a release workflow on `main` that builds and pushes the tag from inside GitHub Actions.** The workflow is `workflow_dispatch`-only, takes a `version` input, and runs against the commit on `main`. It does, in order:
   - Asserts the input matches `v[0-9]+\.[0-9]+\.[0-9]+` (and any extension your scheme allows).
   - Creates a signed tag object on the workflow's `HEAD` using a key whose public part is in `.github/allowed_signers`.
   - Runs `git verify-tag` against `.github/allowed_signers` as the gate — exits non-zero before pushing if verification fails.
   - Pushes the new tag using a token tied to a bypass actor on the tag-protection ruleset (the `millsymills-org-bot-writer` GitHub App is the obvious choice; it already has `contents: write` and is wired through OIDC).
   - The existing `release.yml` (which only runs `git verify-tag` post-push) stays — it becomes a redundant audit signal on the same SHA, kept until the new flow has run cleanly at least three times.

Bypass-actor wiring: declare the writer App as a `bypass_actors` entry on the tag-protection ruleset with `bypass_mode = "always"`. The App's installation ID is already a known constant in `terraform.tfvars` / workflow secrets. No other identity can push `v*` tags.

Acceptance criteria (#22):
- A direct `git push origin v…` from a maintainer's laptop is rejected by the ruleset (`creation = true`).
- A `workflow_dispatch` run of `release.yml` (the new flow) with a valid version succeeds; a run with a tag-object signed by an unlisted key fails before the push step runs.
- The Plan-1 completed-doc bullet "Signed-tag enforcement … gate moves into a release workflow that validates tag signatures before publishing" is resolved.

## Consequences

- `creation = true` on the tag-protection ruleset is **breaking** the moment it goes from `evaluate` to `active`. Until the new workflow lands and is wired to a bypass actor, the org cannot cut a `v*` tag at all. Sequence: (a) land the new release workflow + bypass-actor wiring as one PR with `enforcement = "evaluate"` and `creation = true`; (b) run the new workflow against a smoke-test tag (e.g. `v0.0.0-test`) and confirm push succeeds via the App; (c) attempt a direct `git push origin v…` and confirm rule fires in evaluate-mode (rule-insights records a violation); (d) flip `enforcement = "active"` in a follow-up — alongside or after PR #16 if observation windows overlap.
- The release flow now executes from `main`, so the maintainer can no longer cut a tag from a feature branch. This is a deliberate consequence; it mirrors the apply-flow-only-on-main constraint already enforced for OpenTofu changes.
- Key management gets a hard dependency on the workflow's signing key. The writer App's deploy keys do not sign tag objects — that needs a dedicated SSH signing key (or sigstore/cosign equivalent) provisioned via Secrets Manager and pulled to `${RUNNER_TEMP}` at `0600`, mirroring the App-PEM pattern in `tofu-apply.yml`. If the signing key is lost, releases are blocked until a new key is added to `.github/allowed_signers`.
- The post-push `release.yml`'s value drops from "primary gate" to "audit witness." Keep it for one quarter or three runs, whichever is later, then delete.
- Solo-owner concentration risk: with both ruleset bypass and the App PEM available, the maintainer can still push an unsigned tag by misusing the App. That is an accepted residual; the threat model in the Plan-1 spec already treats the writer App as trusted-to-the-org-admin level.
- Provider validation: `creation = true` on `target = "tag"` is supported (the `creation`/`update`/`deletion` triple is documented under "Rules Configuration" as target-agnostic). No provider change needed.

## Alternatives considered

- **(a) `required_workflows` on the tag ruleset.** Not available on the Free plan; this is the cleanest mechanism if the org ever moves to Team or Enterprise. Revisit on plan change.
- **(b) `required_status_checks` on the tag ruleset.** Semantically broken as analyzed above — the only workflow that produces the gating check is itself triggered by the push being gated. Rejected.
- **(c) Status quo + auto-cleanup bot.** Leave `creation = false`, keep post-push `release.yml`, add a bot that deletes (via the writer App, which can bypass `deletion = true`) tags whose `verify-signed-tag` fails. Cheaper but leaves a window where a bad tag is visible/clonable; loses the "prevented at push" property #22 explicitly requires. Rejected as primary; recorded as a fallback.
- **(d) Do nothing.** Rejected — the Plan-1 deferred-item list and the issue both call for closure.

## References

- Issue [#22](https://github.com/millsymills-com/millsymills-com-org/issues/22) — Plan-2: make release-tag verification a required check for `v*` refs.
- PR [#17](https://github.com/millsymills-com/millsymills-com-org/pull/17) — the post-push `release` workflow.
- ADR [0001](./0001-gate-bypass-mitigation.md) — establishes `required_workflows` is Enterprise-only on Free.
- `modules/ruleset-tag-protection/main.tf` — inline note explaining why `required_signatures` does not cover tag objects.
- `docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md` — "Signed-tag enforcement" under deliberately-deferred.
