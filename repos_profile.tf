# The org profile repo (`.github`, renders profile/README.md on the org page)
# was created out-of-band but its tofu resource was left tainted: the provider's
# repo-create path PATCHes web_commit_signoff_required, which the org's enforced
# commit signoff rejects with 422, so the create errored after the repo existed.
#
# A tainted resource forces destroy+recreate on every apply, and recreate would
# both re-hit the 422 and collide on the (archived) name. Forget the tainted
# entry from state WITHOUT destroying the live repo; it is re-adopted by import
# in a follow-up once state is clean.
removed {
  from = module.org_profile_repo.github_repository.this

  lifecycle {
    destroy = false
  }
}
