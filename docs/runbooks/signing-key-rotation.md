# Runbook: rotate the release-tag SSH signing key

This runbook covers rotation of the SSH **signing private key** used by the workflow-mediated release flow described in ADR-0002. ADR-0002 names key loss / compromise as a release-blocking risk; this is the procedure that fixes that risk before it occurs and limits damage when it does.

The signing key is distinct from the `millsymills-org-bot-writer` GitHub App's PEM. The App PEM authenticates the push; the signing key produces the tag object's SSH signature. They live in different Secrets Manager entries and rotate independently.

## Forward-looking status

ADR-0002 implementation is tracked in issue #36 and has not yet landed. Until #36 ships, no signing key exists in Secrets Manager and there is nothing to rotate; pre-#36 release tags are pushed manually by the maintainer using their personal SSH key (the existing entry in `.github/allowed_signers`). This runbook describes the steady-state procedure that applies once #36 lands. The first "rotation" after #36 will in practice be the initial key provisioning — same procedure with no prior key to remove in PR-2.

## Where the key lives

- **Private key**: AWS Secrets Manager secret `github-signing-key/release-tag` (final name to be confirmed during the #36 implementation). Encrypted with `alias/tfstate-millsymills` KMS key. Versioned via Secrets Manager's `AWSCURRENT` / `AWSPREVIOUS` staging labels.
- **Public key (in-tree)**: `.github/allowed_signers`. The release workflow points `git verify-tag` at this file via `gpg.ssh.allowedSignersFile` before pushing. Format: one principal per line, `<email> namespaces="git" <key-type> <base64-key>`.
- **Fingerprint reference**: any rotation PR description must cite both the outgoing and incoming keys' SHA-256 fingerprints (the `SHA256:...` form produced by `ssh-keygen -lf`).

## Who can rotate

Any operator who is a GitHub org owner AND has write access to the `github-signing-key/release-tag` secret in AWS Secrets Manager (currently `mills` user with full admin via console session, since the routine read-only IAM identity cannot put-secret-value).

Under the current solo-owner posture, that's a single person. The two-PR shape below is the substitute for a second reviewer; do not collapse it.

## Triggers

Permitted reasons to rotate:

- **Suspected compromise.** Treat as emergency rotation — see below.
- **Scheduled rotation.** Once a year, or when an audit explicitly requires it.
- **Key holder departure.** If the maintainer who holds the corresponding private-key access leaves.
- **Algorithm migration.** If `ed25519` is ever deprecated for `git verify-tag`'s purposes, or a stronger algorithm is adopted org-wide.

Not permitted:

- Routine "freshness" rotations on a sub-annual cadence. The Secrets Manager + IAM trust pin gives the key strong protection at rest; rotating frequently adds risk (more steps where something can go wrong) without proportionate benefit.
- Rotating to change algorithm without an explicit decision recorded as an ADR amendment or new ADR.

## Procedure (steady-state, two PRs)

Step 0 — open a tracking issue titled `signing-key-rotation: <reason> <YYYY-MM-DD>`. The two PRs below link to it; it is the audit-trail home.

### 1. Generate the new keypair locally

```bash
# Use ed25519 to match the existing key family.
ssh-keygen -t ed25519 -C "release-tag-signing $(date +%Y-%m-%d)" -N '' \
  -f ~/.ssh/release-signing-key-new
# Capture both fingerprints:
ssh-keygen -lf ~/.ssh/release-signing-key-new.pub
# Note the SHA256:... value. Record it in the tracking issue.

# Also capture the OUTGOING key's fingerprint, by pulling the current
# public part out of the live Secrets Manager entry's metadata or by
# reading it from the in-tree allowed_signers file:
ssh-keygen -lf /tmp/current-public.pub
```

### 2. Upload the new private key to Secrets Manager

```bash
aws secretsmanager put-secret-value \
  --secret-id github-signing-key/release-tag \
  --secret-string file://$HOME/.ssh/release-signing-key-new \
  --version-stages AWSPENDING
```

`AWSPENDING` keeps the key versioned but **not yet active**; the release workflow continues to use `AWSCURRENT` until step 4 promotes the new version.

### 3. PR-1: add the new public key alongside the old in `.github/allowed_signers`

Open a PR that appends a second principal line to `.github/allowed_signers` matching the new key. Do not remove the existing line. Keep one principal per line:

```
andyandymillsmills@gmail.com namespaces="git" ssh-ed25519 <existing-base64>
release-tag-signing-2026-NN namespaces="git" ssh-ed25519 <new-base64>
```

(Substitute the actual key data and a meaningful principal label that includes the rotation date.)

PR description requirements:

- Link to the tracking issue from step 0.
- State both SHA-256 fingerprints — outgoing and incoming — verbatim.
- State the reason for rotation.
- Note that `release.yml` (or its ADR-0002 successor) will accept tags signed by either key after merge.

Merge PR-1. The release workflow can now verify tags signed by either key.

### 4. Promote the new key in Secrets Manager + smoke-test

```bash
# Move AWSCURRENT to point at the new version. The current AWSCURRENT
# version is automatically demoted to AWSPREVIOUS.
NEW_VERSION_ID=$(aws secretsmanager describe-secret \
  --secret-id github-signing-key/release-tag \
  --query 'VersionIdsToStages | to_entries[] | select(.value[] == "AWSPENDING") | .key' \
  --output text)
aws secretsmanager update-secret-version-stage \
  --secret-id github-signing-key/release-tag \
  --version-stage AWSCURRENT \
  --move-to-version-id "$NEW_VERSION_ID"
```

Cut a smoke-test release using the post-ADR-0002 workflow_dispatch flow:

```bash
gh workflow run release.yml -F version=v0.0.<smoke>-rotation-test
```

Watch the run; confirm `verify-signed-tag` passes. The tag now exists on the repo signed by the new key.

### 5. PR-2: remove the old public key from `.github/allowed_signers`

Open a second PR that deletes the outgoing principal line, leaving only the new key in the file. PR description requirements:

- Link to the same tracking issue and PR-1.
- Restate both fingerprints.
- State that the smoke-test release in step 4 succeeded (link the workflow run).

Merge PR-2. The old key is now invalid for `git verify-tag`; any tag signed by it will fail the release workflow's verification step.

### 6. Archive the old Secrets Manager version

```bash
# Inspect the current staging:
aws secretsmanager describe-secret --secret-id github-signing-key/release-tag

# After AWSPREVIOUS retention is no longer wanted (default Secrets Manager
# behavior auto-deletes versions with no staging labels). Optionally
# explicitly delete the old version:
OLD_VERSION_ID=...
aws secretsmanager update-secret-version-stage \
  --secret-id github-signing-key/release-tag \
  --version-stage AWSPREVIOUS \
  --remove-from-version-id "$OLD_VERSION_ID"
```

If the old key is suspected-compromised, delete its private material from the local laptop (`shred -u ~/.ssh/<old-key>`) and revoke any other places it may have been used.

### 7. Close the tracking issue

Include in the close comment:

- Start and end timestamps (UTC).
- Both fingerprints one more time.
- Links to PR-1, the smoke-test release run, and PR-2.

## Emergency rotation (suspected key compromise)

If the signing key is suspected to be in attacker hands, the steady-state procedure is too slow. The minimal-time variant:

1. Skip step 1 of "generate locally on the operator's existing laptop." Instead generate the new key on a known-clean machine (e.g., an EC2 instance launched from a fresh AMI, or a hardware-token-backed laptop).
2. Land PR-1 (add new pubkey) and PR-2 (remove old pubkey) in **back-to-back PRs without an observation period**. The cost of accepting tags signed by a compromised key is higher than the cost of briefly losing the ability to sign.
3. Between PR-1 merging and PR-2 merging, revoke the old key in Secrets Manager (`update-secret-version-stage` to remove `AWSCURRENT` from the old version) so even the existing release workflow cannot use it for new signatures.
4. Audit the existing `v*` tags: list them and verify each against the in-tree `allowed_signers` post-rotation. Any that fail were signed by the compromised key; treat each as a potential supply-chain incident and follow the standard incident-response procedure.
5. After PR-2 merges, open a post-mortem issue describing the suspected compromise, the timeline of detection, and any tags that were retroactively invalidated.

The audit-trail expectation is **stricter** in the emergency variant: the post-mortem issue is mandatory.

## What this runbook is not

- It is not a procedure for rotating the `millsymills-org-bot-writer` App PEM. That key authenticates pushes, not signatures; its rotation involves Secrets Manager + the GitHub App settings page and is documented separately (or in `bootstrap/github-bootstrap.md` once that section is added).
- It is not a procedure for rotating the user's personal SSH commit-signing key. That key is currently in `.github/allowed_signers` (it is what `release.yml` verifies pre-ADR-0002) but its rotation follows the same two-PR pattern; the differences are immaterial.

## Cross-references

- ADR-0002 `docs/adr/0002-required-signed-tag-check.md` — the design that introduces the signing key and the threat model that motivates separation of signing key from App PEM.
- Issue #36 — the implementation rollout for ADR-0002. Until #36 lands, this runbook describes a future-state procedure.
- `.github/allowed_signers` — in-tree verification list.
- `docs/runbooks/ruleset-break-glass.md` — sibling runbook for tag-protection ruleset emergencies (e.g., needing to delete a tag pushed under a compromised key requires break-glass).
- `bootstrap/aws-output.json` — `SECRETSMANAGER_ARN_PREFIX` / KMS key ARN used for the signing key entry.
