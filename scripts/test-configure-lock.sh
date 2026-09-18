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

read_fifo_line() {
  local timeout_seconds="$1"
  local fifo_path="$2"

  timeout "${timeout_seconds}" bash -c 'IFS= read -r line < "$1"; printf "%s\\n" "$line"' bash "${fifo_path}"
}

cleanup() {
  if [[ -n "${holder_pid}" ]]; then
    kill "${holder_pid}" 2>/dev/null || true
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
  local after_lock_script=""
  local ready_path=""
  local release_path=""
  local configure_ready_path=""
  local configure_release_path=""
  local ready=""
  local reached_status=""

  command -v cmake >/dev/null 2>&1 || fail "cmake is required"
  mkdir -p "${repo_root}/build"
  tmp_root="$(mktemp -d "${repo_root}/build/configure-lock.XXXXXX")"
  build_dir="${tmp_root}/build"
  lock_path="${build_dir}/.pid0-configure.lock"
  holder_script="${tmp_root}/hold-lock.cmake"
  after_lock_script="${tmp_root}/after-lock.cmake"
  ready_path="${tmp_root}/lock-ready"
  release_path="${tmp_root}/lock-release"
  configure_ready_path="${tmp_root}/configure-ready"
  configure_release_path="${tmp_root}/configure-release"
  mkdir -p "$(dirname -- "${lock_path}")"
  mkfifo "${ready_path}" "${release_path}" "${configure_ready_path}" "${configure_release_path}"

  cat > "${holder_script}" <<'EOF'
file(LOCK "$ENV{PID0_CONFIGURE_LOCK}" GUARD PROCESS TIMEOUT 10)
file(WRITE "$ENV{PID0_CONFIGURE_LOCK_READY}" "ready\n")
file(READ "$ENV{PID0_CONFIGURE_LOCK_RELEASE}" ignored)
EOF
  cat > "${after_lock_script}" <<'EOF'
file(WRITE "$ENV{PID0_CONFIGURE_LOCK_TEST_READY}" "reached\n")
file(READ "$ENV{PID0_CONFIGURE_LOCK_TEST_RELEASE}" ignored)
EOF

  PID0_CONFIGURE_LOCK="${lock_path}" \
    PID0_CONFIGURE_LOCK_READY="${ready_path}" \
    PID0_CONFIGURE_LOCK_RELEASE="${release_path}" \
    cmake -P "${holder_script}" > "${tmp_root}/holder.log" 2>&1 &
  holder_pid="$!"
  ready="$(read_fifo_line 5 "${ready_path}")" ||
    fail "configure lock holder did not acquire the lock"
  [[ "${ready}" == "ready" ]] || fail "configure lock holder sent an invalid ready signal"

  PID0_CONFIGURE_LOCK_TEST_READY="${configure_ready_path}" \
    PID0_CONFIGURE_LOCK_TEST_RELEASE="${configure_release_path}" \
    cmake --preset debug -B "${build_dir}" \
      -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES="${after_lock_script}" \
      > "${tmp_root}/configure.log" 2>&1 &
  local configure_pid="$!"
  if ready="$(read_fifo_line 1 "${configure_ready_path}")"; then
    fail "configuration passed the lock while the holder owned it: ${ready}"
  else
    reached_status="$?"
  fi
  [[ "${reached_status}" -eq 124 ]] ||
    fail "configuration did not wait for the holder before the post-lock checkpoint"
  printf 'release\n' > "${release_path}"
  wait "${holder_pid}"
  holder_pid=""
  ready="$(read_fifo_line 5 "${configure_ready_path}")" ||
    fail "configuration did not reach the post-lock checkpoint after release"
  [[ "${ready}" == "reached" ]] || fail "configuration sent an invalid post-lock signal"
  printf 'continue\n' > "${configure_release_path}"
  wait "${configure_pid}"
  printf 'test-configure-lock.sh: configure lock contract ok\n'
}

main "$@"
