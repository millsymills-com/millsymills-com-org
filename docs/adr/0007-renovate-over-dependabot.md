# 0007. Renovate over Dependabot, with bounded automerge

## Status

Proposed.

ADR numbers 0003–0006 are reserved for the Plan-2 portfolio decisions in issue #46; this ADR takes the next free number rather than jumping the queue.

## Context

Dependency updates across the fleet are hand-merged today, and the volume no longer fits the maintenance budget.

Measured on 2026-08-21 across both accounts (`millsmillsymills`, 71 repos; `millsymills-com`, 10 repos):

| | |
| --- | --- |
| Repos with `.github/dependabot.yml` | 12 |
| Repos with a Renovate config | 0 |
| Repos with a manifest or workflows and no update bot at all | 42 (29 uv-Python, 8 npm, 7 Docker, 31 with workflows to bump) |
| Dependabot PRs opened to date | 485 |
| — merged | 273 |
| — closed unmerged | 180 |
| — open | 32 |

The oldest of those configs dates to 2025-08 (`resurgent`); ten of the twelve were added between 2026-04 and 2026-06. Run rate is roughly 120 PRs/month from 12 repos. 37% of PRs raised were closed without merging, which is pure review cost with no landed change. Extending the current arrangement to the 42 uncovered repos would roughly quadruple the volume.

Every one of the twelve existing configs converges on the same policy — `interval: weekly`, `cooldown.default-days: 7`, and one group per ecosystem matching `*` — with two refinements worth preserving:

- `unifi-mcp`, `unraid-mcp`, and `gandi-mcp` split dev tooling from runtime dependencies so a test-only bump does not ride along with a shipped one.
- `resurgent` splits majors into their own PR, with an inline note recording why: a grouped merge carried `docker/metadata-action` v5→v6 through without anyone reading the changelog (its issue #160).

So the policy is already settled and already duplicated twelve times. What is missing is (a) a way to express it once and (b) a way for the routine tail of it to land without a human.

### Why the missing piece cannot be Dependabot

Dependabot has no automerge and GitHub has stated it will not add one — "auto-merge will not be supported in GitHub-native Dependabot for the foreseeable future … we're concerned about auto-merge being used to quickly propagate a malicious package across the ecosystem." In January 2026 GitHub went further and removed the `@dependabot merge`, `@dependabot squash and merge`, and `@dependabot cancel merge` comment commands, directing users to "GitHub's built-in UI, the GitHub CLI, and the REST API." The documented path is now a per-repo workflow pairing `dependabot/fetch-metadata` with `gh pr merge --auto`.

That path costs a workflow file, a pinned third-party action, and a `harden-runner` egress allowlist in each of 54 repos, all maintained by hand — the same duplication problem one level up.

Dependabot also has no org-level update configuration. Auto-triage rules and grouped security updates can be set org-wide; the `dependabot.yml` that decides *what gets updated and when* cannot. Eighty-one repos means eighty-one files.

## Decision

Adopt Renovate as the version-update bot for both accounts. Keep Dependabot **alerts** — they are GitHub-native, already declared by `github_repository_vulnerability_alerts` in `modules/repo-baseline`, and Renovate consumes them through `vulnerabilityAlerts`.

Three parts.

### 1. One shared preset, hosted in the org profile repo

The policy lives at `renovate-config.json` in `millsymills-com/.github` and is referenced as `local>millsymills-com/.github:renovate-config`. Repos carry a one-line `renovate.json` that extends it and nothing else.

`.github` is chosen over a new `renovate-config` repo deliberately. Renovate's org-level preset lookup checks for a `.{{platform}}` repo with a `renovate-config.json` under the same owner and, when it finds one, offers it as the sole extended preset in the onboarding PR — so each repo's onboarding arrives pre-wired. `.github` also already exists and is already adopted into state by `repos_profile.tf`, whose header records the convention this follows: tofu owns the repo shell, content lands via a normal PR on the repo itself.

The alternative mechanism, Renovate's *inherited config*, needs no file in the target repo at all, but it requires a repository literally named `renovate-config` holding `org-inherited-config.json`, and it applies only within an organization. The 59 private repos on the `millsmillsymills` **user** account are outside any org and cannot be reached by it. Rather than run two mechanisms, both accounts extend the one public preset — cross-account works because `.github` is public. Revisit if the user-account repos ever move into the org.

### 2. Automerge, bounded at the major boundary

`platformAutomerge` (GitHub's native auto-merge) is used rather than Renovate's own merge, so every required check still gates the merge and the merge commit is written and signed by GitHub.

Automerged: patch and minor updates, GitHub Actions digest pins, Docker digest pins, and `lockFileMaintenance`.

Not automerged, ever: major updates, and anything arriving through `vulnerabilityAlerts`. Majors are held because of the `docker/metadata-action` incident above. Security updates are held for a subtler reason, and it is the reason the twelve existing configs all carry a 7-day cooldown, stated in `ubiquiti-research`'s config: "a freshly published version is when a compromised release is most likely to still be live." A security alert is exactly the case where the cooldown must be waived for speed, so waiving the cooldown *and* the human at once would remove both defenses simultaneously. Security fixes therefore skip the cooldown and the weekly window, and wait for a person.

`minimumReleaseAge: "7 days"` carries the existing `cooldown.default-days: 7` forward as the routine-path defense, and `osvVulnerabilityAlerts` adds malicious-package detection that Dependabot's config does not express.

### 3. Baseline change: squash-only, auto-merge capability on

`modules/repo-baseline/main.tf` changes two settings for every repo in the org, this management repo included:

- `allow_auto_merge = false` → `true`. Without it `platformAutomerge` has nothing to enqueue. This grants a capability only; auto-merge remains opt-in per pull request and still waits on every required check.
- `allow_rebase_merge = true` → `false`. This is a latent bug independent of Renovate. The default-branch ruleset sets `required_signatures`, and GitHub does not sign the commits it writes for a rebase-and-merge — it replays the author's commits, for which it holds no key. A rebase merge therefore lands unverified commits that `required_signatures` rejects, wedging the PR. Renovate v39 reordered its merge-strategy autodiscovery to prefer squash for exactly this reason, but the repo setting is the durable fix and it protects hand-merges too. Squash is left as the only method; merge commits were already off and are separately excluded by `required_linear_history`.

## Consequences

- **Mend is now in the trust boundary.** The hosted Renovate app takes `contents: write` and `pull-requests: write` across both accounts, including 59 private repos, most of them security research. This is the real cost of the decision and it is not mitigated, only accepted: a self-hosted runner removes Mend but restores the per-repo workflow maintenance the decision exists to eliminate, and reintroduces the commit-signing problem (self-hosted Renovate needs `platformCommit` to produce verified commits). If the private research repos are judged too sensitive, the defensible split is Renovate on the public org repos and nothing on the private ones — not Dependabot-plus-54-automerge-workflows.
- **Free tier limits the cadence.** Mend Renovate Community Cloud gives one concurrent job per org and scans active repos every four hours. Adequate for a weekly schedule; it will not feel instant.
- **Automerge conflicts with an explicit global rule and the conflict is deliberate.** The global `CLAUDE.md` PR-session discipline says authoring and merging are separate sessions and forbids `gh pr merge` in an authoring session. Automerged dependency PRs are a carved-out exception, recorded here so a later session does not read it as drift and revert it.
- **Automerge is only as good as the repo's required checks, and coverage is uneven.** GitHub auto-merge waits on required checks, so `platformAutomerge` inherits whatever gate the repo happens to have. Note which way this fails: a repo with *no* required check does not merge instantly, it does not automerge at all. GitHub only offers auto-merge on a pull request that cannot already be merged, so on a clean squash-only PR the `enablePullRequestAutoMerge` mutation is rejected. At least one required check is what makes automerge *function*; the checks' quality is what makes it *safe*. Measured 2026-08-21:

  | Repo | Required status checks |
  | --- | --- |
  | `unifi-mcp`, `unraid-mcp` | `Lint & Format`, `Type Check`, `Bandit Security Scan`, `Test (Python 3.13)`, `Dependency Review`, `CI Pass` |
  | `flipperzero-mcp` | `static`, `test`, `audit`, `analyze` |
  | `shortcut-mcp` | `lint`, `types`, `test`, `security` |
  | `gandi-mcp` | `static`, `test (3.13)`, `audit` |
  | `protonmail-mcp` | `test` |
  | `millsymills-com-org` | `actionlint`, `analyze (actions)`, `gate-verified`, `gitleaks`, `zizmor` |
  | `.github` | **none** |
  | user-account repos with Dependabot today | **none** (`resurgent`, `a2a-security-research`, `ellingson-a2a-signed-card`, `ubiquiti-research`); `millsymills.com` has a ruleset but no required checks, and its own `dependabot.yml` header records its CI as `workflow_dispatch`-only |

  Enable automerge on the top four rows. `protonmail-mcp`'s single `test` check is a thin gate for a Go dependency bump — it gets automerge only once it has lint and vet checks. Leave `automerge: false` on the user-account repos until each has at least one required check; the preset is the wrong place to fix a missing CI pipeline.
- **`rebaseWhen: "behind-base-branch"` in the preset is load-bearing, not tuning.** Every ruleset here sets `strict_required_status_checks_policy: true`, and GitHub auto-merge does *not* update an out-of-date head branch — updating is a human action, and merge queues are GitHub's documented answer. Under any volume that means the first merge to `main` leaves every other automerge-pending PR behind base and stalled indefinitely. Renovate rebasing its own branches is what breaks that livelock, at the cost of a fresh CI run per rebase. Do not relax the key to reduce CI minutes; if stalls appear anyway the sanctioned route is a merge queue, which would require adding a `merge_group` trigger to every required workflow or the checks never report at all. Weakening `strict` is not an option here — `CLAUDE.md` makes not weakening the `gate-verified` path a hard rule.
- **The management repo needs a local override for GitHub Actions updates.** `gate-verified` fails a PR whose `.github/workflows/tofu-plan.yml` blob differs from `main` unless the PR carries a maintainer-applied `workflow-update` label. Renovate cannot apply that label, and `workflow_run` does not refire on `pull_request: labeled`, so an actions bump that touches `tofu-plan.yml` cannot clear its own gate. It blocks rather than bypasses — the safe direction — but it blocks permanently. This repo's `renovate.json` therefore extends the shared preset and overrides `github-actions` back to `automerge: false`; clearing such a PR means applying the label and forcing a fresh `tofu` run by hand.
- **`.github` holds the preset every other repo extends, and has no required check of its own.** A change there changes automerge policy fleet-wide, so it is the highest-leverage file in this design. Having no required check makes it structurally ineligible for platform auto-merge, per the mechanism above, so the capability grant does not expose it — but that is a side effect, not a control. Do not onboard `.github` to Renovate; it carries no manifests worth updating and the onboarding would only add a path for the bot to touch the policy file. A required check on `.github` is the durable fix and is not in this change.
- **The `dependencies` label must exist per repo.** The preset labels PRs `dependencies`, which five repos already use. Renovate warns and continues where the label is missing, so this degrades rather than breaks; making it uniform is a separate change to `modules/repo-baseline`.
- **The twelve `dependabot.yml` files must be deleted as each repo is onboarded**, not left alongside Renovate. Two bots on one manifest means duplicate PRs and races on the same lockfile.
- The `resurgent` config's `pre-commit` ecosystem has a Renovate equivalent (`pre-commit` manager, opt-in via `config:recommended`); its `pip` ecosystem maps to `pip_requirements` — that repo uses `requirements.txt`, not `uv.lock`, and is the noisiest of the twelve at 168 PRs.

## Alternatives considered

- **Dependabot plus a shared reusable automerge workflow.** One workflow in `.github`, called by a small caller workflow per repo. Cuts the duplication but does not remove it — still 54 caller files, 54 `harden-runner` allowlists, and no org-level `dependabot.yml`, so the update policy stays duplicated regardless. Rejected: it pays most of the migration cost for a fraction of the benefit.
- **Self-hosted Renovate in GitHub Actions.** Keeps Mend out of the trust boundary. Rejected for now on the grounds above; it is the fallback if the Mend posture is later judged unacceptable, and the preset written here transfers unchanged.
- **Do nothing and let the backlog sit.** Rejected: 42 repos with manifests currently get no version updates at all, which is a worse security posture than the PR volume it avoids.

## References

- `modules/repo-baseline/main.tf`, `modules/repo-baseline/tests/baseline.tftest.hcl` — the baseline change.
- `repos_profile.tf` — the "tofu owns the shell, content lands by PR" convention the preset placement follows.
- `millsymills-com/.github` → `renovate-config.json` — the preset itself.
- dependabot/dependabot-core#1973, dependabot/feedback#954 — GitHub's position on automerge.
- GitHub changelog, 2026-01-27 — removal of the Dependabot PR comment commands.
- renovatebot/renovate#32016 — merge-strategy reorder for signed commits.
- <https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification> — rebase-and-merge commits are not signature-verified.
- <https://docs.renovatebot.com/config-presets/> — org-level preset lookup in a `.github` repo.
- <https://docs.renovatebot.com/mend-hosted/hosted-apps-config/> — inherited config; Community Cloud resource tiers.
