#!/usr/bin/env bash

set -euo pipefail

# These are tiny test helpers that keep shell test failures readable.

# This stops the test right away with one clear failure message.
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# This checks that two values are exactly the same.
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-expected values to match}"

  if [[ "$expected" != "$actual" ]]; then
    fail "$message: expected [$expected], got [$actual]"
  fi
}

# This checks that a file contains the expected text.
assert_file_contains() {
  local needle="$1"
  local file_path="$2"
  local message="${3:-expected file substring not found}"

  if ! grep -Fq -- "$needle" "$file_path"; then
    fail "$message: missing [$needle] in $file_path"
  fi
}

# This checks that a file does not contain unexpected text.
assert_file_not_contains() {
  local needle="$1"
  local file_path="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$file_path"; then
    fail "$message: unexpected [$needle] in $file_path"
  fi
}
