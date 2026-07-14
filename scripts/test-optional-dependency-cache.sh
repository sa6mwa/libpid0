#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
tmp_root=""

fail() {
  printf 'test-optional-dependency-cache.sh: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${tmp_root}" ]] || rm -rf -- "${tmp_root}"
}
trap cleanup EXIT

main() {
  local toolchain_cache="${CPKT_TOOLCHAIN_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/c.pkt.systems/toolchains}"
  local build_dir=""

  command -v cmake >/dev/null 2>&1 || fail "cmake is required"
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/libpid0-optional-dependency-cache.XXXXXX")"
  build_dir="${tmp_root}/build"

  env -u HOME -u XDG_CACHE_HOME -u CPKT_DEPENDENCY_CACHE \
    CPKT_TOOLCHAIN_CACHE="${toolchain_cache}" \
    cmake --preset debug -B "${build_dir}" \
      -DPID0_BUILD_TESTS=OFF -DPID0_BUILD_EXAMPLES=OFF >/dev/null
  if grep -q '^CPKT_DEPENDENCY_CACHE:' "${build_dir}/CMakeCache.txt"; then
    fail "dependency-free configuration resolved CPKT_DEPENDENCY_CACHE"
  fi
  printf 'test-optional-dependency-cache.sh: dependency-free configure contract ok\n'
}

main "$@"
