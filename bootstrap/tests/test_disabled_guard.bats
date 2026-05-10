#!/usr/bin/env bats

setup() {
  # shellcheck disable=SC2155
  export BOOTSTRAP_DIR="$(mktemp -d)"
  cp "${BATS_TEST_DIRNAME}/../aws-bootstrap.sh" "${BOOTSTRAP_DIR}/aws-bootstrap.sh"
  cp -r "${BATS_TEST_DIRNAME}/../lib" "${BOOTSTRAP_DIR}/"
  chmod +x "${BOOTSTRAP_DIR}/aws-bootstrap.sh"
}

teardown() {
  rm -rf "${BOOTSTRAP_DIR}"
}

@test "aws-bootstrap.sh exits non-zero when .disabled exists and --force not passed" {
  touch "${BOOTSTRAP_DIR}/.disabled"
  run "${BOOTSTRAP_DIR}/aws-bootstrap.sh" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to run"* ]]
}

@test "aws-bootstrap.sh proceeds when .disabled exists and --force passed" {
  touch "${BOOTSTRAP_DIR}/.disabled"
  run "${BOOTSTRAP_DIR}/aws-bootstrap.sh" --dry-run --force
  [ "$status" -eq 0 ]
}

@test "aws-bootstrap.sh proceeds when .disabled does not exist" {
  run "${BOOTSTRAP_DIR}/aws-bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
}
