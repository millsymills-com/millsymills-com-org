# Runbook: ruleset break-glass via `enforcement = "disabled"`

This procedure exists for the **rare** case where an org-level ruleset blocks a write that must legitimately happen and there is no in-rule path forward. The default-branch ruleset's inline comment (`modules/ruleset-default-branch/main.tf` lines 56-58) points here.

It is not a routine bypass. It is not a way to skip a failing required check on a normal PR. It is a recovery path for cases where the ruleset itself is the obstacle and the obstacle is wrong.

## When this procedure is permitted

Permitted use:

- The default-branch ruleset is blocking a write that is correct on its merits, and the rule cannot be revised in advance (e.g., a one-off `force-push` to recover from a corrupt or hostile commit on `main`; a fast-forward that the ruleset rejects because of a misconfigured rule that needs to be fixed in the same window).
- The tag-protection ruleset is blocking a tag operation that is correct on its merits and cannot be revised in advance.
- The management-repo `management-repo-checks` ruleset is blocking a merge because a required-check workflow has a bug that cannot be fixed without first merging a fix (chicken-and-egg).

Not permitted:

- Routine merges where a normal required check is failing because the change is bad. Fix the change.
- Routine merges where a normal required check is failing because the check is flaky. Re-run the check.
- "Just this once" exceptions for normal work. The cost of using break-glass is high (audit trail, two PRs, snapshot work) precisely so that it stays rare.
- Any write that could be done by amending the rule itself in a single PR. Amend the rule.

The solo-owner posture (`require_code_owner_review` and `require_last_push_approval` are off) means there is no second-maintainer approval gate on this procedure. The audit trail below is the substitute.

## Procedure

Break-glass is **two PRs**, not one. Both go through the normal PR → CI plan → merge → CI apply pipeline. No local `tofu apply`.

1. **Snapshot the relevant ruleset's rule-suites state.**

    ```bash
    # Org default-branch ruleset (ID 16259943) — same call for tag-protection (16260826).
    gh api 'orgs/millsymills-com/rulesets/16259943/rule-suites?per_page=50' \
      > rule-suites-default-branch-before.json
    ```

    Requires an `admin:org`-scoped PAT or the reader App's installation token.

2. **PR 1: disable the ruleset.** Open a PR that flips the relevant module's `enforcement` argument from `"active"` to `"disabled"`. For the default-branch ruleset:

    ```hcl
    module "ruleset_default_branch" {
      source = "./modules/ruleset-default-branch"

      enforcement = "disabled"  # break-glass: see docs/runbooks/ruleset-break-glass.md, issue #NN
    }
    ```

    The PR description must include:
    - Which rule is the obstacle, and which write is being blocked.
    - Why the rule cannot be revised instead.
    - The expected duration of the disabled window. Target minutes-to-hours, not days.
    - A link to the tracking issue created in step 0 below.

    Land PR 1 normally. The `tofu-apply` workflow flips the ruleset to `disabled` on `main`.

3. **Perform the necessary work.** Do the write that the ruleset was blocking. Document the exact commands or PRs involved in the tracking issue. Keep the disabled window short.

4. **PR 2: re-enable the ruleset.** Open a second PR that restores `enforcement = "active"`. Do not modify other arguments in the same PR. Land it.

5. **Snapshot the rule-suites state after re-enabling.**

    ```bash
    gh api 'orgs/millsymills-com/rulesets/16259943/rule-suites?per_page=50' \
      > rule-suites-default-branch-after.json
    ```

6. **Close out the audit trail** in the tracking issue:
    - Attach both the before and after JSON snapshots.
    - Note the exact start and end timestamps of the disabled window (PR 1 apply completion → PR 2 apply completion).
    - Note what was done during the window.
    - Note any rule-suites entries between the snapshots that look unexpected.

## Tracking issue (step 0)

Open this *before* PR 1. It is the canonical audit-trail home for the procedure.

Title: `break-glass: ruleset disabled <YYYY-MM-DD> — <short reason>`

Body template:

```
## Context
Which ruleset, which rule, which write being blocked, why.

## Justification
Why the rule cannot be revised in advance.

## Plan
PR 1 (link), planned work, PR 2 (link), expected window duration.

## Snapshots
- Pre:  attached after step 1.
- Post: attached after step 5.

## Window
- Disabled at:  <UTC timestamp, after PR 1 apply>
- Re-enabled at: <UTC timestamp, after PR 2 apply>

## Notes
Free-form. What ran, what was observed, anything notable about rule-suites entries during the window.
```

## bypass_actors is not break-glass

The default-branch ruleset has `bypass_actors` deliberately unset. Direct bypasses are routine paths, not break-glass; tracking and audit trail for them would be much weaker. The management-repo ruleset (`repos_meta.tf`) and the tag-protection ruleset both rely on workflow identity (`millsymills-org-bot-writer` App) for legitimate writes; that is plumbed via OIDC + ruleset configuration in normal code, not via this procedure.

If you find yourself reaching for break-glass because a workflow needs a routine bypass, the right answer is to add the workflow's identity to `bypass_actors` in the relevant ruleset and do it through a normal PR. That is a *rule revision*, not a break-glass.

## Cross-references

- `modules/ruleset-default-branch/main.tf:56-58` — module comment that points at this runbook.
- `modules/ruleset-default-branch/variables.tf` — `enforcement` variable, accepts `"active" | "evaluate" | "disabled"`.
- `modules/ruleset-tag-protection/main.tf` + `variables.tf` — same pattern for the tag-protection ruleset.
- `docs/superpowers/specs/2026-05-09-millsymills-org-design.md` — original Plan-1 design covering the org-wide ruleset rollout.
- Issue #10 — the evaluate→active flip; PR #16 — the flip itself.
- Issue #40 — this runbook.
