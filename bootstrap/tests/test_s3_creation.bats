#!/usr/bin/env bats

setup() {
  export AWS_REGION="us-west-1"
  export STATE_BUCKET="tfstate-millsymills-test"
}

@test "dry-run prints S3 bucket creation plan with correct name" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would create S3 bucket"* ]]
  [[ "$output" == *"tfstate-millsymills"* ]]
}

@test "dry-run prints versioning, public-block, and KMS-SSE bucket policy" {
  run bash "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" --dry-run
  [[ "$output" == *"versioning"* ]]
  [[ "$output" == *"public access block"* ]]
  [[ "$output" == *"TLS-only"* ]]
}
