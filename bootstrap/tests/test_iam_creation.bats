#!/usr/bin/env bats

@test "dry-run mentions OIDC provider for github actions" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"token.actions.githubusercontent.com"* ]]
}

@test "dry-run mentions all three IAM roles" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"gha-millsymills-org-tofu-plan"* ]]
  [[ "$output" == *"gha-millsymills-org-tofu-apply"* ]]
  [[ "$output" == *"gha-millsymills-org-tofu-drift"* ]]
}

@test "dry-run mentions environment-pinned trust policies" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"environment:tofu-plan"* ]]
  [[ "$output" == *"environment:tofu-apply"* ]]
  [[ "$output" == *"environment:tofu-drift"* ]]
}
