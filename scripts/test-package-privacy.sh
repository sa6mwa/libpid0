#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
package_verify="${script_dir}/package-verify.sh"
tmp_root=""

fail() {
  printf 'test-package-privacy.sh: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${tmp_root}" ]]; then
    rm -rf -- "${tmp_root}"
  fi
}
trap cleanup EXIT

write_release_fixture() {
  local fixture_dist="$1"
  local leak="$2"
  local header_path="${fixture_dist}/libpid0-0.0.0.h"
  local artifact_path="${fixture_dist}/libpid0-0.0.0.h.gz"

  mkdir -p "${fixture_dist}"
  cat > "${header_path}" <<EOF
/* Version: 0.0.0 */
typedef int (*pid0_submain_fn)(int, char **);
int pid0_run(pid0_submain_fn submain, int argc, char **argv);
${leak}
EOF
  gzip -n -c "${header_path}" > "${artifact_path}"
  (
    cd "${fixture_dist}"
    sha256sum "$(basename -- "${artifact_path}")" > libpid0-0.0.0-CHECKSUMS
  )
}

assert_release_fixture_rejected() {
  local name="$1"
  local leak="$2"
  local variable_name="${3:-}"
  local variable_value="${4:-}"
  local fixture_dist="${tmp_root}/${name}/dist"
  local output_path="${tmp_root}/${name}/verify.log"

  write_release_fixture "${fixture_dist}" "${leak}"
  if [[ -n "${variable_name}" ]]; then
    if env "${variable_name}=${variable_value}" PID0_DIST_DIR="${fixture_dist}" "${package_verify}" \
      > "${output_path}" 2>&1; then
      fail "${name} leak was accepted in a checksum-listed release fixture"
    fi
  elif PID0_DIST_DIR="${fixture_dist}" "${package_verify}" > "${output_path}" 2>&1; then
    fail "${name} leak was accepted in a checksum-listed release fixture"
  fi
  grep -F 'contains local path material' "${output_path}" >/dev/null ||
    fail "${name} rejection did not report local path material"
}

assert_binary_path_rejected() {
  local binary_fixture="${tmp_root}/binary-fixture"
  local output_path="${tmp_root}/binary-fixture.log"
  local cache_root="${tmp_root}/binary-cache"

  mkdir -p "${binary_fixture}" "${cache_root}"
  printf '\0\377%s\0' "${cache_root}" > "${binary_fixture}/payload.bin"
  if env CPKT_DEPENDENCY_CACHE="${cache_root}" "${package_verify}" --verify-paths "${binary_fixture}" fixture \
    > "${output_path}" 2>&1; then
    fail "binary cache path leak was accepted"
  fi
  grep -F 'contains local path material' "${output_path}" >/dev/null ||
    fail "binary cache path rejection did not report local path material"
}

assert_elf_rpath_rejected() {
  local fixture_root="${tmp_root}/rpath-fixture"
  local fixture_dist="${fixture_root}/dist"
  local stage_root="${fixture_root}/stage/libpid0-0.0.0-x86_64-linux-gnu"
  local output_path="${fixture_root}/verify.log"

  command -v cc >/dev/null 2>&1 || fail "cc is required for the ELF RPATH fixture"
  command -v ar >/dev/null 2>&1 || fail "ar is required for the ELF RPATH fixture"
  mkdir -p "${stage_root}/include/pid0" \
    "${stage_root}/lib/cmake/pid0" \
    "${stage_root}/lib/pkgconfig" \
    "${stage_root}/share/doc/libpid0"
  cat > "${fixture_root}/pid0.c" <<'EOF'
int pid0_fixture_symbol(void) { return 0; }
EOF
  cat > "${stage_root}/include/pid0/pid0.h" <<'EOF'
int pid0_fixture_symbol(void);
EOF
  cc -fPIC -c "${fixture_root}/pid0.c" -o "${fixture_root}/pid0.o"
  ar rcs "${stage_root}/lib/libpid0.a" "${fixture_root}/pid0.o"
  cc -shared "${fixture_root}/pid0.o" -Wl,-soname,libpid0.so.0 -Wl,-rpath,/opt/libpid0-fixture \
    -o "${stage_root}/lib/libpid0.so.0.0.0"
  ln -s libpid0.so.0.0.0 "${stage_root}/lib/libpid0.so.0"
  ln -s libpid0.so.0 "${stage_root}/lib/libpid0.so"
  printf '%s\n' 'include(CMakeFindDependencyMacro)' > "${stage_root}/lib/cmake/pid0/pid0Config.cmake"
  printf '%s\n' 'set(PACKAGE_VERSION "0.0.0")' > "${stage_root}/lib/cmake/pid0/pid0ConfigVersion.cmake"
  printf '%s\n' '# fixture' > "${stage_root}/lib/cmake/pid0/pid0Targets.cmake"
  printf '%s\n' '# fixture' > "${stage_root}/lib/cmake/pid0/pid0Targets-release.cmake"
  printf '%s\n' 'prefix=${pcfiledir}/..' > "${stage_root}/lib/pkgconfig/pid0.pc"
  printf '%s\n' 'fixture license' > "${stage_root}/share/doc/libpid0/LICENSE"
  printf '%s\n' 'fixture readme' > "${stage_root}/share/doc/libpid0/README.md"
  mkdir -p "${fixture_dist}"
  (
    cd "${fixture_root}/stage"
    tar --sort=name --owner=0 --group=0 --numeric-owner -czf \
      "${fixture_dist}/libpid0-0.0.0-x86_64-linux-gnu.tar.gz" \
      "libpid0-0.0.0-x86_64-linux-gnu"
  )
  (
    cd "${fixture_dist}"
    sha256sum libpid0-0.0.0-x86_64-linux-gnu.tar.gz > libpid0-0.0.0-CHECKSUMS
  )
  if PID0_DIST_DIR="${fixture_dist}" "${package_verify}" > "${output_path}" 2>&1; then
    fail "non-relocatable ELF RPATH was accepted in a release fixture"
  fi
  grep -F 'contains non-relocatable ELF runtime path' "${output_path}" >/dev/null ||
    fail "ELF RPATH rejection did not report non-relocatable runtime metadata"
}

main() {
  local dependency_cache="${tmp_root}/dependency-cache"
  local toolchain_cache="${tmp_root}/toolchain-cache"

  [[ -x "${package_verify}" ]] || fail "missing package verifier: ${package_verify}"
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/libpid0-package-privacy.XXXXXX")"
  assert_release_fixture_rejected repository "${repo_root}"
  assert_release_fixture_rejected home "${HOME}"
  assert_release_fixture_rejected repository-file-url "file://${repo_root}"
  assert_release_fixture_rejected home-file-url "file://${HOME}"
  assert_release_fixture_rejected dependency-cache "${dependency_cache}" CPKT_DEPENDENCY_CACHE "${dependency_cache}"
  assert_release_fixture_rejected toolchain-cache "${toolchain_cache}" CPKT_TOOLCHAIN_CACHE "${toolchain_cache}"
  assert_binary_path_rejected
  assert_elf_rpath_rejected
  printf 'test-package-privacy.sh: package privacy contract ok\n'
}

main "$@"
