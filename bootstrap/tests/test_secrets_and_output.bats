#!/usr/bin/env bats

@test "dry-run mentions both Secrets Manager placeholders" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"github-app-key/millsymills-org-bot-writer"* ]]
  [[ "$output" == *"github-app-key/millsymills-org-bot-reader"* ]]
}

@test "dry-run mentions writing aws-output.json" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"aws-output.json"* ]]
}
