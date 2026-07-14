#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
dependency_module="${repo_root}/cmake/CPKTDependencies.cmake"
https_server="${script_dir}/test-https-server.py"
tmp_root=""
server_pid=""

fail() {
  printf 'test-dependency-cache.sh: %s\n' "$*" >&2
  exit 1
}

stop_server() {
  if [[ -n "${server_pid}" ]]; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    server_pid=""
  fi
}

cleanup() {
  stop_server
  if [[ -n "${tmp_root}" ]]; then
    rm -rf -- "${tmp_root}"
  fi
}
trap cleanup EXIT

start_server() {
  local ready_path="${tmp_root}/server-ready"

  rm -f -- "${ready_path}" "${request_log}"
  PYTHONDONTWRITEBYTECODE=1 python3 "${https_server}" \
    --root "${tmp_root}/server" \
    --cert "${certificate_path}" \
    --key "${key_path}" \
    --ready "${ready_path}" \
    --access-log "${request_log}" &
  server_pid="$!"
  for _ in $(seq 1 100); do
    if [[ -s "${ready_path}" ]]; then
      server_port="$(< "${ready_path}")"
      download_url="https://127.0.0.1:${server_port}/fixture.tar.gz"
      return
    fi
    sleep 0.05
  done
  fail "HTTPS fixture server did not become ready"
}

run_probe() {
  local stage="$1"
  local result="$2"

  TEST_DEP_CACHE="${cache_root}" \
    TEST_DEP_STAGE="${stage}" \
    TEST_DEP_MODULE="${dependency_module}" \
    TEST_DEP_SHA256="${archive_sha256}" \
    TEST_DEP_URL="${download_url}" \
    TEST_DEP_CAINFO="${certificate_path}" \
    TEST_DEP_RESULT="${result}" \
    cmake -DPID0_DEPENDENCY_DOWNLOAD_ATTEMPTS=1 -P "${probe_path}"
}

assert_staged_fixture() {
  local result="$1"

  [[ -f "${result}" ]] || fail "probe did not report a source root"
  [[ -f "$(< "${result}")/payload" ]] || fail "probe did not stage the verified fixture"
}

assert_no_temporary_archives() {
  if find "$(dirname -- "${cached_archive}")" -maxdepth 1 -type f -name 'fixture.tar.gz.tmp.*' -print -quit | grep -q .; then
    fail "dependency acquisition left a temporary archive"
  fi
}

assert_no_fixture_bytecode() {
  if find "${script_dir}/__pycache__" -maxdepth 1 -type f -name 'test-https-server.*.pyc' -print -quit 2>/dev/null | grep -q .; then
    fail "HTTPS fixture server left Python bytecode in the repository"
  fi
}

main() {
  local fixture_root=""
  local archive_path=""
  local initial_stage=""
  local initial_result=""
  local concurrent_one_stage=""
  local concurrent_one_result=""
  local concurrent_two_result=""
  local concurrent_stage=""
  local stage_lock=""
  local lock_holder_path=""
  local lock_ready_path=""
  local elapsed=""
  local request_count=""
  local fixture_bytecode_dir="${script_dir}/__pycache__"
  local fixture_bytecode="${fixture_bytecode_dir}/libpid0-clean-fixture.pyc"

  [[ -f "${dependency_module}" ]] || fail "missing dependency module: ${dependency_module}"
  [[ -x "${https_server}" ]] || fail "missing HTTPS fixture server: ${https_server}"
  command -v cmake >/dev/null 2>&1 || fail "cmake is required"
  command -v openssl >/dev/null 2>&1 || fail "openssl is required"
  command -v python3 >/dev/null 2>&1 || fail "python3 is required"

  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/libpid0-dependency-cache.XXXXXX")"
  cache_root="${tmp_root}/shared-cache"
  fixture_root="${tmp_root}/fixture/fixture-1.0.0"
  archive_path="${tmp_root}/server/fixture.tar.gz"
  probe_path="${tmp_root}/probe.cmake"
  lock_holder_path="${tmp_root}/hold-stage-lock.cmake"
  certificate_path="${tmp_root}/certificate.pem"
  key_path="${tmp_root}/key.pem"
  request_log="${tmp_root}/requests.log"
  initial_stage="${tmp_root}/initial-stage"
  initial_result="${tmp_root}/initial-result"

  mkdir -p "${fixture_root}" "$(dirname -- "${archive_path}")"
  printf 'dependency-cache-fixture\n' > "${fixture_root}/payload"
  dd if=/dev/urandom of="${fixture_root}/large-payload" bs=1M count=2 status=none
  tar -C "${tmp_root}/fixture" -czf "${archive_path}" "fixture-1.0.0"
  archive_sha256="$(sha256sum "${archive_path}" | awk '{ print $1 }')"
  cached_archive="${cache_root}/archives/sha256/${archive_sha256}/fixture.tar.gz"

  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=127.0.0.1' \
    -addext 'subjectAltName=IP:127.0.0.1' \
    -keyout "${key_path}" \
    -out "${certificate_path}" >/dev/null 2>&1
  cat > "${probe_path}" <<'EOF'
set(CPKT_DEPENDENCY_CACHE "$ENV{TEST_DEP_CACHE}")
set(PID0_DEPENDENCY_BUILD_ROOT "$ENV{TEST_DEP_STAGE}")
set(CMAKE_TLS_CAINFO "$ENV{TEST_DEP_CAINFO}")
include("$ENV{TEST_DEP_MODULE}")
pid0_acquire_verified_archive(
  fixture
  "$ENV{TEST_DEP_URL}"
  "$ENV{TEST_DEP_SHA256}"
  fixture_archive)
pid0_stage_verified_archive(
  fixture
  "1.0.0"
  "$ENV{TEST_DEP_SHA256}"
  "${fixture_archive}"
  fixture_source)
if(NOT EXISTS "${fixture_source}/payload")
  message(FATAL_ERROR "verified archive was not staged")
endif()
file(WRITE "$ENV{TEST_DEP_RESULT}" "${fixture_source}\n")
EOF
  cat > "${lock_holder_path}" <<'EOF'
file(LOCK "$ENV{TEST_DEP_STAGE_LOCK}" GUARD PROCESS TIMEOUT 10)
file(WRITE "$ENV{TEST_DEP_LOCK_READY}" "ready\n")
execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 2)
EOF

  start_server
  run_probe "${initial_stage}" "${initial_result}"
  assert_staged_fixture "${initial_result}"
  [[ "$(sha256sum "${cached_archive}" | awk '{ print $1 }')" == "${archive_sha256}" ]] ||
    fail "initial cache miss did not publish a verified archive"
  [[ "$(wc -l < "${request_log}")" == "1" ]] || fail "initial cache miss did not issue exactly one download"
  assert_no_temporary_archives

  stop_server
  rm -rf -- "${initial_stage}"
  rm -f -- "${initial_result}"
  run_probe "${initial_stage}" "${initial_result}"
  assert_staged_fixture "${initial_result}"

  rm -rf -- "${initial_stage}"
  rm -f -- "${initial_result}"
  printf 'corrupt dependency cache entry\n' > "${cached_archive}"
  if run_probe "${initial_stage}" "${initial_result}" > "${tmp_root}/corrupt-probe.log" 2>&1; then
    fail "corrupt cache entry was accepted"
  fi
  grep -F 'verified download failed' "${tmp_root}/corrupt-probe.log" >/dev/null ||
    fail "corrupt cache entry did not report a verified download failure"
  [[ ! -e "${cached_archive}" ]] || fail "corrupt cache entry was not removed"
  assert_no_temporary_archives
  [[ ! -e "${initial_stage}" ]] || fail "corrupt cache entry was extracted"

  rm -rf -- "${cache_root}"
  concurrent_stage="${tmp_root}/concurrent-stage"
  concurrent_one_stage="${concurrent_stage}"
  concurrent_one_result="${tmp_root}/concurrent-one-result"
  concurrent_two_result="${tmp_root}/concurrent-two-result"
  start_server
  run_probe "${concurrent_one_stage}" "${concurrent_one_result}" > "${tmp_root}/concurrent-one.log" 2>&1 &
  local concurrent_one_pid="$!"
  run_probe "${concurrent_stage}" "${concurrent_two_result}" > "${tmp_root}/concurrent-two.log" 2>&1 &
  local concurrent_two_pid="$!"
  wait "${concurrent_one_pid}"
  wait "${concurrent_two_pid}"
  assert_staged_fixture "${concurrent_one_result}"
  assert_staged_fixture "${concurrent_two_result}"
  [[ "$(sha256sum "${cached_archive}" | awk '{ print $1 }')" == "${archive_sha256}" ]] ||
    fail "concurrent acquisition published a non-verified archive"
  request_count="$(wc -l < "${request_log}")"
  [[ "${request_count}" == "1" ]] || fail "concurrent acquisition issued ${request_count} downloads instead of one"
  assert_no_temporary_archives

  stage_lock="${concurrent_stage}/locks/fixture-1.0.0-${archive_sha256}.lock"
  lock_ready_path="${tmp_root}/stage-lock-ready"
  TEST_DEP_STAGE_LOCK="${stage_lock}" \
    TEST_DEP_LOCK_READY="${lock_ready_path}" \
    cmake -P "${lock_holder_path}" > "${tmp_root}/stage-lock-holder.log" 2>&1 &
  local lock_holder_pid="$!"
  for _ in $(seq 1 100); do
    [[ -f "${lock_ready_path}" ]] && break
    sleep 0.05
  done
  [[ -f "${lock_ready_path}" ]] || fail "stage lock holder did not acquire the lock"
  SECONDS=0
  run_probe "${concurrent_stage}" "${concurrent_one_result}"
  elapsed=${SECONDS}
  wait "${lock_holder_pid}"
  (( elapsed >= 1 )) || fail "staging did not wait for the shared stage lock"

  stop_server
  assert_no_fixture_bytecode

  mkdir -p -- "${fixture_bytecode_dir}"
  : > "${fixture_bytecode}"

  "${repo_root}/scripts/clean.sh"
  [[ ! -e "${fixture_bytecode_dir}" ]] || fail "clean left Python bytecode in the repository"
  [[ -f "${cached_archive}" ]] || fail "clean removed the shared dependency archive cache"
  printf 'test-dependency-cache.sh: dependency cache contract ok\n'
}

main "$@"
