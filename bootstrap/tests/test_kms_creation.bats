#!/usr/bin/env bats

@test "dry-run mentions KMS key alias and rotation" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias/tfstate-millsymills"* ]]
  [[ "$output" == *"annual rotation"* ]]
}

@test "dry-run mentions bucket policy with TLS deny and KMS deny" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"deny non-TLS"* ]]
  [[ "$output" == *"deny non-KMS"* ]]
}
