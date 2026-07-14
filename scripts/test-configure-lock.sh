#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
tmp_root=""
holder_pid=""

fail() {
  printf 'test-configure-lock.sh: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${holder_pid}" ]]; then
    wait "${holder_pid}" 2>/dev/null || true
  fi
  if [[ -n "${tmp_root}" ]]; then
    rm -rf -- "${tmp_root}"
  fi
}
trap cleanup EXIT

main() {
  local build_dir=""
  local lock_path=""
  local holder_script=""
  local ready_path=""
  local elapsed=""

  command -v cmake >/dev/null 2>&1 || fail "cmake is required"
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/libpid0-configure-lock.XXXXXX")"
  build_dir="${tmp_root}/build"
  lock_path="${build_dir}/.pid0-configure.lock"
  holder_script="${tmp_root}/hold-lock.cmake"
  ready_path="${tmp_root}/lock-ready"
  mkdir -p "$(dirname -- "${lock_path}")"

  cat > "${holder_script}" <<'EOF'
file(LOCK "$ENV{PID0_CONFIGURE_LOCK}" GUARD PROCESS TIMEOUT 10)
file(WRITE "$ENV{PID0_CONFIGURE_LOCK_READY}" "ready\n")
execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 2)
EOF

  PID0_CONFIGURE_LOCK="${lock_path}" \
    PID0_CONFIGURE_LOCK_READY="${ready_path}" \
    cmake -P "${holder_script}" > "${tmp_root}/holder.log" 2>&1 &
  holder_pid="$!"
  for _ in $(seq 1 100); do
    [[ -f "${ready_path}" ]] && break
    sleep 0.05
  done
  [[ -f "${ready_path}" ]] || fail "configure lock holder did not acquire the lock"

  cmake --preset debug -B "${build_dir}" > "${tmp_root}/configure.log" 2>&1 &
  local configure_pid="$!"
  for _ in $(seq 1 100); do
    kill -0 "${configure_pid}" 2>/dev/null || break
    sleep 0.01
  done
  if find "${build_dir}/CMakeFiles" -name CMakeCCompiler.cmake -print -quit 2>/dev/null | grep -q .; then
    fail "configuration performed compiler detection before acquiring the build-directory lock"
  fi
  wait "${holder_pid}"
  holder_pid=""
  SECONDS=0
  while ! find "${build_dir}/CMakeFiles" -name CMakeCCompiler.cmake -print -quit 2>/dev/null | grep -q . &&
    (( SECONDS < 5 )); do
    sleep 0.05
  done
  elapsed=${SECONDS}
  (( elapsed < 5 )) || fail "configuration did not resume after the build-directory lock was released"
  wait "${configure_pid}"
  printf 'test-configure-lock.sh: configure lock contract ok\n'
}

main "$@"
