#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
build_dir="${repo_root}/build/debug"
config_header="${build_dir}/_deps/cmocka-build/config.h"

fail() {
  printf 'test-cmocka-configure.sh: %s\n' "$*" >&2
  exit 1
}

cmake --fresh --preset debug
cmake --build --preset debug --target pid0-unit-tests
ctest --test-dir "${build_dir}" --output-on-failure -R '^pid0-unit-tests$'

[[ -f "${config_header}" ]] || fail "cmocka did not generate config.h"
grep -Eq '^#define HAVE_UINTPTR_T 1$' "${config_header}" ||
  fail "cmocka was not configured with uintptr_t support"

printf 'test-cmocka-configure.sh: clean cmocka configure contract ok\n'
