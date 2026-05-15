---
title: millsymills-com portfolio content rollout (Plan-2 spec)
date: 2026-05-14
status: draft — pending final user review
audience: Andrew Mills (millsmillsymills) — solo owner of millsymills-com org
supersedes: nothing
extends: docs/superpowers/specs/2026-05-09-millsymills-org-design.md
---

# millsymills-com portfolio content: Plan-2 spec

## Goal

Land the four portfolio repos named in Plan-1 (Section 3) as **production-quality public artifacts**, in an order chosen so each repo earns its own pin before the next one starts. Each repo must hold up as the *only* artifact a reader sees from this org — pretend that's the only one they'll click.

## Constraints (inherited from Plan-1, restated)

- **Audience:** security-product recruiters, enterprise CISOs, consulting clients. Three audiences, one shape per repo — no marketing-mode prose.
- **Sensitivity:** Trail of Bits is never named. No content competes with their commercial offerings (smart-contract, fuzzing/program-analysis, binary analysis). All examples generalized.
- **Tier:** Org Free. Public repos only. All Plan-1 ruleset guarantees apply (signed commits, branch protection, required checks).
- **Solo owner:** No `require_code_owner_review`. Authoring + merging are the same person; quality bar comes from CI + ADR discipline, not from review headcount.
- **Maintenance load is the hardest constraint.** Four polished repos > eight stubs. Defer aggressively if cadence is unsustainable.

## What this spec does *not* re-specify

Plan-1 already locked:

- Repo content sketches (Section 3, "MVP repos" table).
- Per-repo README skeleton (Section 7).
- Voice rules (Section 7).
- Pinned-repos ordering for the org page (Section 7).
- ADR format and badge ordering (Section 7).
- Org profile / personal profile README text (Section 7).

This spec sequences them and defines what "done enough to pin" means for each.

---

## Section 1 — Sequencing & gates *(proposed)*

```
.github  (front door)  ──┐
                         │  org-level signal; lowest content lift
                         ▼
controls-as-code (governance)
                         │  GRC / CISO signal; static-site option
                         ▼
terraform-aws-baseline (infra)
                         │  DevSecOps / cloud signal; reusable module
                         ▼
incident-response-runbooks (operations)
                         │  IR / detection signal; playbook library
                         ▼
        ── pinned, all four, MVP narrative complete ──
```

Sequencing rules:

1. **One repo at a time** until the previous repo is *pin-grade* (Section 3 quality bar). The org page shows whatever is pinned; an unfinished repo not pinned is invisible to drive-by visitors.
2. **`.github` always first.** It is the front door. Plan-1 Section 7 already drafts the org-profile README; landing it instantly upgrades the org's perceived completion level. Lowest content lift, highest visual gain.
3. **Pause between repos.** Two weeks minimum between "previous repo pin-grade" and "start next repo content." Lets feedback (recruiter pings, scorecard.dev refresh, dependabot churn) reveal weak spots before stacking new surface area.
4. **Stop at four.** Plan-1's "held back from MVP" list (`mac-mdm-baselines`, `security-awareness-trainings`, `threat-models`, `detection-rules`) stays held until the four MVP repos have been pin-grade for at least one quarter. Don't widen the surface before the core surface is loadbearing.

## Section 2 — Repo creation pattern *(proposed)*

Plan-1 Section 6 already defined "Phase 6 — adding new portfolio repos (steady state)":

> Create `repos/<name>.tf` declaring the repo + its config. Open PR — Tofu plan posted. Merge → apply creates the repo with full security baseline + scaffolding files. Clone, populate content, push (signed commits, normal flow).

Plan-2 refines:

- **Empty-repo gate.** A new portfolio repo lands in Tofu as `is_template = false` + `visibility = "public"` *but* its README is a stub that says "in progress — see [millsymills-com-org](…) for status." This is honest and rules out drive-by linking before the repo is ready.
- **Pin only when pin-grade.** Plan-1 lists the pinned set explicitly. Until a new repo meets the Section 3 quality bar, it stays *un-pinned* — present in the org's repo list but not surfaced on the org page.
- **`repos/<name>.tf` lives next to `repos_existing.tf` and `repos_meta.tf`.** Same module (`./modules/repo-baseline`), same conventions. No new module needed unless a repo's settings genuinely diverge from the baseline.
- **ADRs land with the *first content commit*, not with the repo creation.** An empty repo with ADRs is theatre; ADRs explain decisions readers can verify against shipped code.

## Section 3 — Per-repo pin-grade quality bar *(proposed)*

A portfolio repo is pin-grade when **all** of the following are true:

### Universal bar (all four repos)

- [ ] README follows Plan-1 Section 7 skeleton exactly: one-line "what this is", "Why this exists", "What you get", "How to use it", "What it doesn't do", "Controls implemented" (where applicable), "Receipts."
- [ ] `LICENSE` present. Apache-2.0 unless Plan-1's open-question list resolves otherwise.
- [ ] `SECURITY.md` present (org default workflow via `.github` repo).
- [ ] At least three ADRs in `docs/adr/`, written for an external reader.
- [ ] Badges in the order Plan-1 Section 7 specifies: Scorecard → License → "signed". No CI-status badge.
- [ ] Plan-1 inherited supply-chain controls present and green, each verifiable from the repo's own workflow files:
  - **CodeQL** analysis on push + PR (`github/codeql-action`).
  - **OpenSSF Scorecard** (`ossf/scorecard-action`) on schedule + push, with results published to the Scorecard dashboard.
  - **zizmor** (`woodruffw/zizmor`) on every workflow change.
  - **gitleaks** secret scanning on push + PR.
  - **actionlint** workflow linting on push + PR.
  - **`step-security/harden-runner`** at the top of every job — `egress-policy: block` for credentialed jobs with an explicit allowlist; `egress-policy: audit` for uncredentialed jobs.
  - **All `uses:` pinned to a full commit SHA** with a `# vX.Y.Z` trailing comment; `actions/checkout` uses `persist-credentials: false`.
  - **Dependency Review** (`actions/dependency-review-action`) on every PR.
  - **SBOM + SLSA-3 provenance** generated for every release artifact (per the release flow in ADR-0002 once it lands).
  - **Signed-commits ruleset** active on the default branch — inherited from the management repo's `org-baseline` module; no per-repo work to enable.
- [ ] All of the above workflows green for at least 7 consecutive days.
- [ ] OpenSSF Scorecard score ≥ 8.0/10. Each below-threshold item has an ADR explaining the deliberate gap.
- [ ] A signed `v0.1.0` release exists. The release uses the (per ADR-0002) workflow-mediated signing flow once that lands.
  - **Contingent path if ADR-0002 impl (#36) has not merged by pin-grade time:** manual signed tag from the maintainer's laptop using a key whose public part is in `.github/allowed_signers`, plus the existing post-push `release.yml` audit. Note the deviation in the repo's first release ADR and migrate at next release after #36 lands.
- [ ] Org-profile README's "thread" table entry is filled in with a concrete one-line description.

### Per-repo bar (in addition to universal)

| Repo | Pin-grade-only criteria | Audience evidence (what 90s of skimming proves) |
|---|---|---|
| `.github` | Org-profile README rendered correctly on the org page; default workflow templates referenced from at least one other repo; `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md` ship as org defaults inherited by every new repo | **Recruiter:** owner runs a real org with an attention-to-detail front door, not a personal account with stray repos. **CISO:** vulnerability-disclosure surface exists and is unambiguous. |
| `controls-as-code` | Cross-mapping of NIST CSF + SOC2 + ISO 27001 + CIS in machine-readable YAML; static-site generator emits to GH Pages (deferred if effort > 1 working day); each control has at least one cross-reference to a *file or commit* in another `millsymills-com` repo (no theoretical-only entries) | **CISO:** owner can talk to a control framework and prove implementation from code, not slides. **Client:** controls catalog is the kind of artifact a consultant would deliver as an audit baseline. |
| `terraform-aws-baseline` | One-apply hardened AWS account from a clean state (CloudTrail, GuardDuty, Security Hub, Config, IAM Identity Center, Access Analyzer, S3 public-block, CIS conformance); module tests via `tofu test` + `mock_provider`; smoke-applied against a throwaway AWS account at least once and the apply receipt linked in `docs/` | **Recruiter (DevSecOps role):** owner ships IaC that actually applies, with tests and a receipt. **Client:** module is reusable as a starter for a new AWS account. |
| `incident-response-runbooks` | At least five playbooks covering identity compromise, AWS console compromise, GitHub OIDC role compromise, GitHub App key leak, supply-chain compromise (dep package); tabletop template that produces a fillable Markdown post-mortem; no real incident details — all generalized | **CISO:** owner has thought through GitHub-org-specific compromise paths most security programs ignore. **Recruiter (security-engineering role):** runbooks are detailed enough to use, not survey-level. |

## Section 4 — Voice & content guardrails *(restated from Plan-1 + extended)*

Plan-1 Section 7 covers voice. Plan-2 additions:

- **Read every page back as a recruiter who has 90 seconds.** If the first 200 words do not state what the repo is, who it serves, and what they can copy, rewrite.
- **No `gh-pages` site without two-week soak.** Static sites attract crawlers and inbound links; if they go down or rot, that is the most visible failure mode in the portfolio. Soak in `gh-pages` branch + PR-preview before merging to the published path.
- **Forbidden patterns (`p41m0n.com` mirror, extended to match global voice rules):**
  - No "passionate", "robust", "comprehensive", "elegant", "best-in-class", "leverage" (as verb).
  - No "critical", "crucial", "essential", "significant" applied to anything that is not literally a critical-severity finding.
  - No emoji except where they are functional UI affordances (checkboxes are fine; ✨ is not).
  - No "thanks to my employer" anywhere. No "views are my own" disclaimer either — it draws attention.
- **Allowed:** dry humor, footnotes referencing controls, code blocks with `# why:` comments, exhibits-as-receipts.

## Section 5 — Maintenance cadence *(proposed)*

Steady-state cost per repo, post-pin:

| Activity | Cadence | Estimated cost |
|---|---|---|
| Dependabot triage (grouped, 7-day cooldown) | Weekly | ~10 min |
| Drift / nightly-CI failure investigation | As needed | ~15 min/event |
| OpenSSF Scorecard score check | Monthly | ~5 min |
| Content refresh (control updates, AWS service changes, new IR scenarios) | Quarterly | ~2-4 hours |
| Release (tag + signed release notes) | Quarterly or on substantive change | ~30 min |

Hard threshold: **if total maintenance > 4 hours/month across all repos, defer the next repo's start.** Burn-out kills portfolio repos faster than any technical decision.

## Section 6 — Risks specific to Plan-2 *(new)*

| Risk | Mitigation |
|---|---|
| **Stale content makes the portfolio look abandoned.** A 6-month-old `terraform-aws-baseline` that doesn't acknowledge a new AWS Security Hub control is worse than not having it. | Quarterly content refresh on the cadence above. Each repo has a `LAST_REVIEWED` line at the bottom of its README; nightly drift posts an issue if that date is > 120 days old. **Sunset policy:** if `LAST_REVIEWED` exceeds 180 days **and** no maintenance PR has merged in the prior 90 days, un-pin the repo and add a `unmaintained` topic. At 365 days exceeded, archive the repo with a redirect ADR explaining the decision. Pre-empts the worst failure mode — pinned-but-rotting — by forcing a visible state change before the rot is externally noticed. |
| **ToB adjacency creeps in.** Threat-modeling content, fuzzing examples, or binary-analysis snippets drift toward employer turf as the corpus grows. | Pre-publish review on every PR that adds content: "would this exact framing be a ToB blog post or commercial demo?" If yes, reframe or cut. |
| **Static site (GH Pages) outage.** Custom-domain Pages on `controls.millsymills.com` (Plan-1 open question) becomes a visible-broken artifact if Pages goes down or DNS rots. | Defer custom domain until `controls-as-code` is pin-grade. Until then, use the default `*.github.io` URL. |
| **Signing key for tag-object enforcement (ADR-0002) blocks releases.** A lost or wrong-permission SSH signing key blocks every portfolio release. | Provisioning runbook updated as part of ADR-0002 impl (#36); key + public-key entry in `.github/allowed_signers` reviewed annually. |
| **Drive-by recruiter sees an unfinished repo.** A non-pin-grade repo with substantive but rough content reads as "this person ships sloppy work." | Section 2 empty-repo gate: stub README + un-pinned until pin-grade. |
| **Plan-1 guarantees regress.** A portfolio-repo PR that turns off a CI workflow or weakens a ruleset undermines the entire "made visible, audited end-to-end" narrative. | The org's `controls-as-code` repo *must* explicitly cite every Plan-1 control — failure to maintain controls visibly violates the published catalog. |

## Section 7 — Acceptance gate for Plan-2 completion *(proposed)*

Plan-2 is complete when:

- [ ] All four MVP repos exist, pin-grade per Section 3.
- [ ] All four MVP repos pinned on the org page in Plan-1 Section 7 order.
- [ ] Personal profile README (`millsmillsymills/.github/profile/README.md`) lands and links to the org.
- [ ] `millsymills.com` ↔ org cross-links are live (`/work` page on `millsymills.com` mirrors pinned repos).
- [ ] `LAST_REVIEWED` dates ≤ 90 days old on every pin-grade repo.
- [ ] One quarter of clean maintenance has elapsed since the fourth pin.

## Section 8 — ADRs to file alongside this spec *(new)*

Plan-1 set the precedent that non-obvious org-level decisions land as ADRs in `docs/adr/`. Plan-2 inherits the same rule. Four decisions in *this* spec qualify and must be filed as separate ADR PRs before the spec is moved from `draft` to `accepted`:

- **ADR-0003 — Plan-2 MVP repo set.** Rationale: why these four (`.github`, `controls-as-code`, `terraform-aws-baseline`, `incident-response-runbooks`), and why not the held-back four (`mac-mdm-baselines`, `security-awareness-trainings`, `threat-models`, `detection-rules`) until the MVP holds for a quarter.
- **ADR-0004 — Public-only posture.** Rationale: every portfolio repo is public from creation; no `.github-private` companion. The portfolio is the artifact a stranger evaluates, so anything not public is invisible.
- **ADR-0005 — `millsymills.com` stays separate.** Rationale: the site is a separate codebase and not absorbed into a GitHub-Pages org site. Cross-linked from `.github`'s org-profile README and from `/work` on the site. Decouples site styling/CMS choices from the org's IaC.
- **ADR-0006 — Maintenance budget cap (≤ 4 hours/month).** Rationale: explicit numeric ceiling because sustainability beats new-repo throughput. Document the trigger that pauses new-repo work and the unwind procedure.

Each ADR PR is independent of this spec PR and of the others. They can be reviewed and accepted in any order; this spec moves to `accepted` only after all four ADRs are merged or explicitly deferred.

## Open questions / unresolved

- **GH Pages custom domain decision** (Plan-1 open question that becomes load-bearing here): defer until `controls-as-code` lands; revisit at pin-grade time. The default `millsymills-com.github.io/controls-as-code` URL is fine for MVP.
- **`FUNDING.yml` contents** (Plan-1 open question): probably omit until `terraform-aws-baseline` is consumed by someone other than the maintainer; then reconsider.
- **Personal `.github/profile/README.md` vs. `.github` org profile** drift: should one act as the canonical and the other a stub-link? Plan-1 Section 7 drafts both; Plan-2 defers the cross-link rules to first-pin time.
- **Social-card workflow** (Plan-1 Section 7 mentions `.github/workflows/social-cards.yml`): build with the `.github` repo or defer to a later iteration? Mid-cost feature; recommend defer until `incident-response-runbooks` is pin-grade.
- **AI-disclosure footer.** If any repo's prose was drafted with an LLM, do we disclose? Recommendation: yes, in `docs/adr/` as a process ADR — earns trust over the alternative of pretending not.

## Decisions ratified

| Decision | Choice | Rationale |
|---|---|---|
| Sequencing | `.github` → `controls-as-code` → `terraform-aws-baseline` → `incident-response-runbooks` | Order chosen to land the front door first; then the highest-signal-per-effort interior repo; then the most-substantive infra repo; then the operationally-focused capstone. Each repo's pin earns the next repo's start. |
| Empty-repo gate | New portfolio repos land in Tofu with stub README + unpinned | Avoids drive-by impression of half-done work; honest about state |
| Pin-grade bar | Universal bar + per-repo bar in Section 3 | Multiple objective criteria; reduces "good enough" drift |
| Maintenance budget | ≤ 4 hours/month across all four repos | Sustainability > new-repo throughput |
| Static-site / custom domain | Default `*.github.io` for MVP; custom domain after `controls-as-code` is pin-grade | Reduces visible-broken surface |
| ToB-adjacency check | Per-PR self-review against "would this be a ToB blog post?" | Lightweight ongoing guardrail |
| Held-back-MVP repos (`mac-mdm-baselines`, `security-awareness-trainings`, `threat-models`, `detection-rules`) | Stay held until four MVP repos have been pin-grade for one full quarter | Caps surface area; protects sustainability budget |

## References

- `docs/superpowers/specs/2026-05-09-millsymills-org-design.md` — Plan-1 spec, particularly Sections 3 + 6 + 7.
- `docs/superpowers/plans/2026-05-09-millsymills-org-bootstrap-and-baseline.completed.md` — Plan-1 outcomes + deferred items list.
- `docs/adr/0001-gate-bypass-mitigation.md` — `gate-verified` mechanism that every portfolio repo will inherit via the management repo's ruleset.
- `docs/adr/0002-required-signed-tag-check.md` — workflow-mediated tag-push flow that every portfolio repo's release process will use.
- `p41m0n.com` — voice / restraint reference.
