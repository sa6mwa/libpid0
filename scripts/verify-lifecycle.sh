#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
presets_path="${repo_root}/CMakePresets.json"
toolchain_path="${repo_root}/cmake/toolchains/cpkt-linux.cmake"
dependency_path="${repo_root}/cmake/CPKTDependencies.cmake"
download_helper_path="${repo_root}/cmake/CPKTDownloadVerifiedArchive.cmake"

require_pattern() {
  local pattern="$1"
  local path="$2"

  if ! grep -Eq "${pattern}" "${path}"; then
    printf 'verify-lifecycle.sh: missing required pattern %s in %s\n' "${pattern}" "${path}" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local path="$2"

  if grep -Eq "${pattern}" "${path}"; then
    printf 'verify-lifecycle.sh: forbidden pattern %s in %s\n' "${pattern}" "${path}" >&2
    exit 1
  fi
}

cmake -S "${repo_root}" --list-presets >/dev/null

for preset in \
  debug \
  valgrind \
  release \
  asan \
  fuzz \
  x86_64-linux-gnu-release \
  x86_64-linux-musl-release \
  aarch64-linux-gnu-release \
  aarch64-linux-musl-release \
  armhf-linux-gnu-release \
  armhf-linux-musl-release; do
  require_pattern "\"name\"[[:space:]]*:[[:space:]]*\"${preset}\"" "${presets_path}"
done

for target_id in \
  x86_64-linux-gnu \
  x86_64-linux-musl \
  aarch64-linux-gnu \
  aarch64-linux-musl \
  armhf-linux-gnu \
  armhf-linux-musl; do
  require_pattern "\"PID0_TARGET_ID\"[[:space:]]*:[[:space:]]*\"${target_id}\"" "${presets_path}"
done

reject_pattern '"name"[[:space:]]*:[[:space:]]*"pkg-' "${presets_path}"
reject_pattern '"PID0_TARGET_ID"[[:space:]]*:[[:space:]]*"arm64-apple-darwin"' "${presets_path}"
reject_pattern 'musl-gcc|aarch64-linux-(gnu|musl)-gcc|arm-linux-(gnu|musl)' "${presets_path}"
require_pattern 'cpkt-linux\.cmake' "${presets_path}"
require_pattern 'pid0-configure\.lock' "${repo_root}/CMakeLists.txt"
require_pattern 'cpkt-toolchains\.sh' "${toolchain_path}"
require_pattern 'CPKT_DEPENDENCY_CACHE' "${dependency_path}"
require_pattern 'print-file-name=libc.so' "${toolchain_path}"
require_pattern 'Pinned compiler selected a libc outside its sysroot' "${toolchain_path}"
require_pattern 'PYTHONDONTWRITEBYTECODE=1' "${repo_root}/scripts/test-dependency-cache.sh"
require_pattern 'scripts/__pycache__' "${repo_root}/scripts/clean.sh"
require_pattern 'file\(LOCK' "${dependency_path}"
require_pattern 'stage_lock' "${dependency_path}"
require_pattern 'PID0_DEPENDENCY_DOWNLOAD_ATTEMPTS' "${dependency_path}"
require_pattern 'CPKTDownloadVerifiedArchive\.cmake' "${dependency_path}"
require_pattern 'string\(RANDOM' "${dependency_path}"
require_pattern 'file\(RENAME' "${dependency_path}"
require_pattern 'EXPECTED_HASH' "${download_helper_path}"
require_pattern 'cmocka\.org/files/2\.0/cmocka-2\.0\.2\.tar\.xz' "${repo_root}/tests/CMakeLists.txt"
reject_pattern 'GIT_REPOSITORY|pkg_check_modules\(CMOCKA' "${repo_root}/tests/CMakeLists.txt"
reject_pattern 'git ls-files --cached --others' "${repo_root}/scripts/package.sh"
require_pattern 'RELEASE_MANIFEST' "${repo_root}/scripts/test_release_from_source.sh"
require_pattern 'grep -R -a' "${repo_root}/scripts/package-verify.sh"
require_pattern 'pid0::pid0_shared' "${repo_root}/scripts/package-verify.sh"
require_pattern 'libpid0-.*PID0_VERSION.*tar' "${repo_root}/cmake/package_checksums.cmake"
require_pattern 'discover_target_tools\.sh" --target-id' "${repo_root}/scripts/package-verify.sh"
require_pattern 'assert_elf_rpath_rejected' "${repo_root}/scripts/test-package-privacy.sh"
require_pattern '^\.NOTPARALLEL:' "${repo_root}/Makefile"
require_pattern '^release-pipeline:' "${repo_root}/Makefile"
require_pattern '^prerelease: release-pipeline$' "${repo_root}/Makefile"
require_pattern '^release: clean release-pipeline$' "${repo_root}/Makefile"
require_pattern '^test-host: build-host$' "${repo_root}/Makefile"
require_pattern '^test-configure-lock:$' "${repo_root}/Makefile"
require_pattern '^test-cmocka-configure:$' "${repo_root}/Makefile"
require_pattern '^test-dependency-cache:$' "${repo_root}/Makefile"
require_pattern '^test-optional-dependency-cache:$' "${repo_root}/Makefile"
require_pattern '^test-toolchain-cache-recovery:$' "${repo_root}/Makefile"
require_pattern '^test-toolchain-bootstrap:$' "${repo_root}/Makefile"
require_pattern '^test-aflpp-resolver:$' "${repo_root}/Makefile"
require_pattern '^test-package-checksums:$' "${repo_root}/Makefile"
require_pattern '^test-package-privacy:$' "${repo_root}/Makefile"
require_pattern '^fuzz-smoke: fuzz$' "${repo_root}/Makefile"
require_pattern 'cpkt-aflpp\.cmake' "${presets_path}"
require_pattern 'CPKT_TOOLCHAIN_LOCK_TIMEOUT:-600' "${repo_root}/scripts/cpkt-toolchains.sh"
require_pattern 'collection_id' "${repo_root}/scripts/cpkt-aflpp.sh"
require_pattern 'CPKT_TOOLCHAIN_LOCK_TIMEOUT:-600' "${repo_root}/scripts/cpkt-aflpp.sh"
[[ -x "${repo_root}/scripts/test-dependency-cache.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable dependency-cache contract test\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-optional-dependency-cache.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable optional dependency-cache contract test\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-toolchain-cache-recovery.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable toolchain cache recovery contract test\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-configure-lock.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable configure-lock contract test\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-toolchain-bootstrap.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable toolchain bootstrap contract test\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-aflpp-resolver.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable AFL++ resolver contract test\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-package-checksums.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable checksum-manifest contract test\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-cmocka-configure.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable cmocka configure contract test\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-https-server.py" ]] || {
  printf 'verify-lifecycle.sh: missing executable HTTPS dependency fixture server\n' >&2
  exit 1
}
[[ -x "${repo_root}/scripts/test-package-privacy.sh" ]] || {
  printf 'verify-lifecycle.sh: missing executable package-privacy contract test\n' >&2
  exit 1
}

printf 'verify-lifecycle.sh: lifecycle preset contract ok\n'
