#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
dist_dir="${PID0_DIST_DIR:-${repo_root}/dist}"
tmp_root=""

cleanup() {
  if [[ -n "${tmp_root}" ]]; then
    rm -rf -- "${tmp_root}"
  fi
}
trap cleanup EXIT

fail() {
  printf 'package-verify.sh: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_entry() {
  local archive_path="$1"
  local entry="$2"

  tar -tzf "${archive_path}" | awk -v entry="${entry}" '$0 == entry { found = 1 } END { exit found ? 0 : 1 }' ||
    fail "${archive_path} is missing ${entry}"
}

require_symlink() {
  local archive_path="$1"
  local link_path="$2"
  local link_target="$3"

  tar -tvzf "${archive_path}" | awk -v link_path="${link_path}" -v link_target="${link_target}" '
    index($0, " " link_path " -> " link_target) > 0 { found = 1 }
    END { exit found ? 0 : 1 }
  ' || fail "${archive_path} does not contain symlink ${link_path} -> ${link_target}"
}

assert_root_owned() {
  local archive_path="$1"

  tar --numeric-owner -tvzf "${archive_path}" | awk '$2 != "0/0" { exit 1 }' ||
    fail "${archive_path} contains non-root owner/group metadata"
}

artifact_version() {
  local first_artifact="$1"

  if [[ "${first_artifact}" =~ ^libpid0-([0-9]+\.[0-9]+\.[0-9]+)(-|\.tar\.gz|\.h\.gz) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  fail "cannot derive version from artifact name: ${first_artifact}"
}

scan_forbidden_paths() {
  local scan_root="$1"
  local artifact_name="$2"
  local dependency_cache="${CPKT_DEPENDENCY_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/c.pkt.systems/deps}"
  local toolchain_cache="${CPKT_TOOLCHAIN_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/c.pkt.systems/toolchains}"
  local forbidden_path=""
  local escaped_path=""
  local -a forbidden_patterns=()
  local grep_output=""

  for forbidden_path in "${repo_root}" "${HOME}" "${dependency_cache}" "${toolchain_cache}"; do
    escaped_path="$(printf '%s\n' "${forbidden_path}" | sed 's/[.[\*^$()+?{}|]/\\&/g')"
    forbidden_patterns+=("${escaped_path}" "file://${escaped_path}")
  done

  grep_output="$(grep -R -a -n -E "$(IFS='|'; printf '%s' "${forbidden_patterns[*]}")" "${scan_root}" 2>/dev/null || true)"
  if [[ -n "${grep_output}" ]]; then
    printf '%s\n' "${grep_output}" | sed -n '1,10p' >&2
    fail "${artifact_name} contains local path material"
  fi
}

verify_elf_metadata() {
  local extract_root="$1"
  local artifact_name="$2"
  local readelf_bin="$3"
  local elf_path=""
  local metadata=""

  [[ -x "${readelf_bin}" ]] || fail "target readelf is unavailable for ${artifact_name}: ${readelf_bin}"

  while IFS= read -r -d '' elf_path; do
    if ! file "${elf_path}" | grep -Eq 'ELF .* (executable|shared object)'; then
      continue
    fi
    metadata="$("${readelf_bin}" -d "${elf_path}" 2>/dev/null || true)"
    if printf '%s\n' "${metadata}" | grep -Eq 'RPATH|RUNPATH'; then
      if printf '%s\n' "${metadata}" | grep -Ev '\$ORIGIN' | grep -Eq 'RPATH|RUNPATH'; then
        fail "${artifact_name} contains non-relocatable ELF runtime path in ${elf_path}"
      fi
      if printf '%s\n' "${metadata}" | grep -Eq "${repo_root}|${HOME}|/tmp|/var/tmp|/usr/local"; then
        fail "${artifact_name} contains local ELF runtime path in ${elf_path}"
      fi
    fi
  done < <(find "${extract_root}" -type f -print0)
}

verify_cmake_consumer() {
  local sdk_root="$1"
  local target_id="$2"
  local compiler="$3"
  local consumer_dir="${tmp_root}/consumer-${target_id}"

  mkdir -p "${consumer_dir}"
  cat > "${consumer_dir}/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.28)
project(pid0_consumer C)
set(CMAKE_C_STANDARD 90)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
find_package(pid0 CONFIG REQUIRED)
add_executable(pid0_static_consumer main.c)
target_link_libraries(pid0_static_consumer PRIVATE pid0::pid0_static)
add_executable(pid0_shared_consumer main.c)
target_link_libraries(pid0_shared_consumer PRIVATE pid0::pid0_shared)
EOF
  cat > "${consumer_dir}/main.c" <<'EOF'
#include <pid0/pid0.h>
static int submain(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 0;
}
int main(int argc, char **argv) { return pid0_run(submain, argc, argv); }
EOF

  cmake -S "${consumer_dir}" -B "${consumer_dir}/build" -G Ninja \
    -DCMAKE_PREFIX_PATH="${sdk_root}" \
    -DCMAKE_C_COMPILER="${compiler}" >/dev/null
  cmake --build "${consumer_dir}/build" >/dev/null
}

verify_pkg_config_consumer() {
  local sdk_root="$1"
  local target_id="$2"
  local compiler="$3"
  local consumer_dir="${tmp_root}/pkgconfig-consumer-${target_id}"
  local cflags=""
  local libs=""

  if ! command -v pkg-config >/dev/null 2>&1; then
    fail "pkg-config is required to verify pkg-config metadata for ${target_id}"
  fi

  mkdir -p "${consumer_dir}"
  cat > "${consumer_dir}/main.c" <<'EOF'
#include <pid0/pid0.h>
static int submain(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 0;
}
int main(int argc, char **argv) { return pid0_run(submain, argc, argv); }
EOF

  cflags="$(PKG_CONFIG_PATH="${sdk_root}/lib/pkgconfig" pkg-config --cflags pid0)"
  libs="$(PKG_CONFIG_PATH="${sdk_root}/lib/pkgconfig" pkg-config --libs pid0)"
  (
    cd "${consumer_dir}"
    # shellcheck disable=SC2086
    "${compiler}" -std=c89 -Wall -Wextra -Wpedantic -Werror ${cflags} main.c ${libs} -o pid0-pkgconfig-consumer
  )
}

verify_binary_archive() {
  local artifact_name="$1"
  local version="$2"
  local target_id="${artifact_name#libpid0-${version}-}"
  local archive_path="${dist_dir}/${artifact_name}"
  local root="libpid0-${version}-${target_id%.tar.gz}"
  local extract_dir="${tmp_root}/extract-${target_id%.tar.gz}"
  local sdk_root="${extract_dir}/${root}"
  local compiler=""
  local readelf_bin=""
  local tool_description=""

  mkdir -p "${extract_dir}"
  tar -xzf "${archive_path}" -C "${extract_dir}"

  require_entry "${archive_path}" "${root}/include/pid0/pid0.h"
  require_entry "${archive_path}" "${root}/lib/libpid0.a"
  require_entry "${archive_path}" "${root}/lib/libpid0.so"
  require_entry "${archive_path}" "${root}/lib/libpid0.so.0"
  require_entry "${archive_path}" "${root}/lib/libpid0.so.${version}"
  require_entry "${archive_path}" "${root}/lib/cmake/pid0/pid0Config.cmake"
  require_entry "${archive_path}" "${root}/lib/cmake/pid0/pid0ConfigVersion.cmake"
  require_entry "${archive_path}" "${root}/lib/cmake/pid0/pid0Targets.cmake"
  require_entry "${archive_path}" "${root}/lib/cmake/pid0/pid0Targets-release.cmake"
  require_entry "${archive_path}" "${root}/lib/pkgconfig/pid0.pc"
  require_entry "${archive_path}" "${root}/share/doc/libpid0/LICENSE"
  require_entry "${archive_path}" "${root}/share/doc/libpid0/README.md"
  require_symlink "${archive_path}" "${root}/lib/libpid0.so" "libpid0.so.0"
  require_symlink "${archive_path}" "${root}/lib/libpid0.so.0" "libpid0.so.${version}"
  assert_root_owned "${archive_path}"

  scan_forbidden_paths "${sdk_root}" "${artifact_name}"
  tool_description="$("${script_dir}/discover_target_tools.sh" --target-id "${target_id%.tar.gz}" \
    --build-dir "${repo_root}/build/${target_id%.tar.gz}-release")"
  readelf_bin="$(awk -F= '$1 == "READELF" { print $2 }' <<<"${tool_description}")"
  verify_elf_metadata "${sdk_root}" "${artifact_name}" "${readelf_bin}"

  compiler="$(awk -F= '$1 == "CC" { print $2 }' <<<"${tool_description}")"
  if [[ -n "${compiler}" ]] && command -v "${compiler}" >/dev/null 2>&1; then
    verify_cmake_consumer "${sdk_root}" "${target_id%.tar.gz}" "${compiler}"
    verify_pkg_config_consumer "${sdk_root}" "${target_id%.tar.gz}" "${compiler}"
  else
    fail "compiler unavailable for install-tree smoke: ${compiler:-<empty>} (${target_id%.tar.gz})"
  fi
}

verify_source_archive() {
  local artifact_name="$1"
  local version="$2"
  local archive_path="${dist_dir}/${artifact_name}"
  local extract_dir="${tmp_root}/source"
  local source_root="${extract_dir}/libpid0-${version}"
  local manifest_file="${source_root}/RELEASE_MANIFEST"
  local listed=""

  mkdir -p "${extract_dir}"
  tar -xzf "${archive_path}" -C "${extract_dir}"
  require_file "${source_root}/VERSION"
  require_file "${manifest_file}"
  [[ "$(tr -d '[:space:]' < "${source_root}/VERSION")" == "${version}" ]] ||
    fail "source archive VERSION does not match ${version}"

  while IFS= read -r listed; do
    [[ -e "${source_root}/${listed}" ]] || fail "source archive manifest lists missing file: ${listed}"
  done < "${manifest_file}"
  (
    cd "${source_root}"
    find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort
  ) > "${tmp_root}/source-archive-files"
  cmp -s "${manifest_file}" "${tmp_root}/source-archive-files" ||
    fail "source archive payload does not exactly match RELEASE_MANIFEST"

  [[ ! -d "${source_root}/.git" ]] || fail "source archive contains .git"
  [[ ! -d "${source_root}/build" ]] || fail "source archive contains build"
  [[ ! -d "${source_root}/dist" ]] || fail "source archive contains dist"
  scan_forbidden_paths "${source_root}" "${artifact_name}"
}

verify_single_header() {
  local artifact_name="$1"
  local version="$2"
  local header_dir="${tmp_root}/single-header"
  local header_path="${tmp_root}/libpid0-${version}.h"

  mkdir -p "${header_dir}"
  header_path="${header_dir}/libpid0-${version}.h"
  gzip -cd "${dist_dir}/${artifact_name}" > "${header_path}"
  grep -F "Version: ${version}" "${header_path}" >/dev/null ||
    fail "single-header artifact does not contain expected version"
  grep -F "int pid0_run(pid0_submain_fn submain, int argc, char **argv)" "${header_path}" >/dev/null ||
    fail "single-header artifact missing public API"
  scan_forbidden_paths "${header_dir}" "${artifact_name}"
}

main() {
  local checksum_count=0
  local checksum_file=""
  local artifact=""
  local version=""
  local -a listed_artifacts=()
  local release_artifact=""

  [[ -d "${dist_dir}" ]] || fail "missing dist directory: ${dist_dir}"
  checksum_count="$(find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f -name 'libpid0-*-CHECKSUMS' | wc -l)"
  [[ "${checksum_count}" == "1" ]] || fail "expected exactly one checksum manifest in ${dist_dir}, found ${checksum_count}"
  checksum_file="$(find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f -name 'libpid0-*-CHECKSUMS' -print)"
  scan_forbidden_paths "${checksum_file}" "$(basename -- "${checksum_file}")"

  (
    cd "${dist_dir}"
    sha256sum -c "$(basename -- "${checksum_file}")" >/dev/null
  )

  mapfile -t listed_artifacts < <(awk '{ print $2 }' "${checksum_file}" | LC_ALL=C sort)
  ((${#listed_artifacts[@]} > 0)) || fail "checksum manifest is empty"
  version="$(artifact_version "${listed_artifacts[0]}")"

  while IFS= read -r release_artifact; do
    [[ "${release_artifact}" == libpid0-"${version}"* ]] ||
      fail "stale release artifact for a different version: ${release_artifact}"
  done < <(find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f \( -name 'libpid0-*.tar.gz' -o -name 'libpid0-*.h.gz' -o -name 'libpid0-*-CHECKSUMS' \) -printf '%f\n' | LC_ALL=C sort)

  [[ ! -e "${dist_dir}/SHA256SUMS" ]] ||
    fail "deprecated checksum manifest must not be present: ${dist_dir}/SHA256SUMS"

  tmp_root="$(mktemp -d "${dist_dir}/.verify.XXXXXX")"

  for artifact in "${listed_artifacts[@]}"; do
    require_file "${dist_dir}/${artifact}"
    case "${artifact}" in
      "libpid0-${version}.tar.gz")
        verify_source_archive "${artifact}" "${version}"
        ;;
      "libpid0-${version}.h.gz")
        verify_single_header "${artifact}" "${version}"
        ;;
      "libpid0-${version}-"*.tar.gz)
        verify_binary_archive "${artifact}" "${version}"
        ;;
      *)
        fail "unexpected checksum-listed artifact: ${artifact}"
        ;;
    esac
  done

  while IFS= read -r release_artifact; do
    printf '%s\n' "${listed_artifacts[@]}" | grep -Fx "${release_artifact}" >/dev/null ||
      fail "release-looking artifact is missing from checksum manifest: ${release_artifact}"
  done < <(find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f \( -name "libpid0-${version}*.tar.gz" -o -name "libpid0-${version}.h.gz" \) -printf '%f\n' | LC_ALL=C sort)

  "${script_dir}/verify-lifecycle.sh"
  "${script_dir}/test-discover-target-tools.sh"
  printf 'package-verify.sh: package verification ok\n'
}

if [[ "${1:-}" == "--verify-paths" ]]; then
  [[ "$#" == "3" ]] || fail "usage: $0 --verify-paths <scan-root> <artifact-name>"
  scan_forbidden_paths "$2" "$3"
  exit 0
fi

main "$@"
