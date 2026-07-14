#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
preset=valgrind

if ! command -v valgrind >/dev/null 2>&1; then
  cat >&2 <<'EOF'
PKT_DIAGNOSTIC_BEGIN
surface=valgrind
phase=prerequisite
status=failed
class=external-tool-unavailable
reason=host-valgrind-not-installed
next=Install Valgrind on the native x86_64 Linux host.
PKT_DIAGNOSTIC_END
EOF
  exit 1
fi

cmake --preset "${preset}"
cmake --build --preset "${preset}"

for test_binary in pid0-unit-tests pid0-single-header-unit-tests pid0-integration-tests; do
  test_path="${repo_root}/build/${preset}/tests/${test_binary}"
  [[ -x "${test_path}" ]] || {
    printf 'valgrind.sh: missing test binary: %s\n' "${test_path}" >&2
    exit 1
  }
  valgrind \
    --leak-check=full \
    --show-leak-kinds=all \
    --track-origins=yes \
    --errors-for-leak-kinds=definite,indirect,possible \
    --error-exitcode=1 \
    "${test_path}"
done

printf 'valgrind.sh: native memory checks passed\n'
