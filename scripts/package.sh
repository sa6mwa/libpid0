#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
dist_dir="${repo_root}/dist"

build_one() {
  local configure_preset="$1"
  local build_dir="${repo_root}/build/${configure_preset}"
  local cache_path="${build_dir}/CMakeCache.txt"
  local release_version=""
  local target_id=""
  local archive_path=""
  local stage_dir=""
  local -a top_entries=()

  cmake --fresh --preset "${configure_preset}"
  cmake --build --preset "${configure_preset}"

  release_version="$(cache_value "${cache_path}" CMAKE_PROJECT_VERSION)"
  target_id="${configure_preset#pkg-}"
  archive_path="${dist_dir}/libpid0-${release_version}-linux-${target_id}.tar.gz"
  stage_dir="$(mktemp -d "${dist_dir}/.stage.XXXXXX")"

  cmake --install "${build_dir}" --prefix "${stage_dir}"
  mapfile -t top_entries < <(find "${stage_dir}" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
  (
    cd "${stage_dir}"
    tar --sort=name --owner=0 --group=0 --numeric-owner -czf "${archive_path}" "${top_entries[@]}"
  )
  rm -rf "${stage_dir}"
}

cache_value() {
  local cache_path="$1"
  local key="$2"
  local value=""

  value="$(awk -F= -v key="${key}" '$1 ~ "^" key ":" { print $2; exit }' "${cache_path}")"
  if [[ -z "${value}" ]]; then
    printf 'package.sh: missing %s in %s\n' "${key}" "${cache_path}" >&2
    exit 1
  fi
  printf '%s\n' "${value}"
}

archive_has_entry() {
  local archive_path="$1"
  local entry="$2"

  tar -tzf "${archive_path}" | awk -v entry="${entry}" '$0 == entry { found = 1 } END { exit found ? 0 : 1 }'
}

assert_archive_has_entry() {
  local archive_path="$1"
  local entry="$2"

  if ! archive_has_entry "${archive_path}" "${entry}"; then
    printf 'package.sh: %s is missing %s\n' "${archive_path}" "${entry}" >&2
    exit 1
  fi
}

assert_archive_symlink() {
  local archive_path="$1"
  local link_path="$2"
  local link_target="$3"

  if ! tar -tvzf "${archive_path}" | awk -v link_path="${link_path}" -v link_target="${link_target}" '
    index($0, " " link_path " -> " link_target) > 0 { found = 1 }
    END { exit found ? 0 : 1 }
  '; then
    printf 'package.sh: %s does not contain symlink %s -> %s\n' \
      "${archive_path}" "${link_path}" "${link_target}" >&2
    exit 1
  fi
}

assert_archive_root_owned() {
  local archive_path="$1"

  if ! tar --numeric-owner -tvzf "${archive_path}" | awk '$2 != "0/0" { exit 1 }'; then
    printf 'package.sh: %s contains non-root owner/group metadata\n' "${archive_path}" >&2
    exit 1
  fi
}

build_single_header() {
  cmake --fresh --preset release
  cmake --build --preset release --target package-single-header
}

validate_archives() {
  local -a archives=()
  local archive_name=""
  local archive_path=""
  local release_version=""

  while IFS= read -r archive_name; do
    archives+=("${archive_name}")
  done < <(find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f -name 'libpid0-*.tar.gz' -printf '%f\n' | LC_ALL=C sort)

  if ((${#archives[@]} == 0)); then
    printf 'package.sh: no release archives found in %s\n' "${dist_dir}" >&2
    exit 1
  fi

  for archive_name in "${archives[@]}"; do
    if [[ "${archive_name}" == *-dev.tar.gz ]]; then
      printf 'package.sh: unexpected split dev archive: %s\n' "${archive_name}" >&2
      exit 1
    fi

    release_version="${archive_name#libpid0-}"
    release_version="${release_version%%-linux-*}"
    archive_path="${dist_dir}/${archive_name}"

    assert_archive_has_entry "${archive_path}" "include/pid0/pid0.h"
    assert_archive_has_entry "${archive_path}" "lib/libpid0.a"
    assert_archive_has_entry "${archive_path}" "lib/libpid0.so"
    assert_archive_has_entry "${archive_path}" "lib/libpid0.so.0"
    assert_archive_has_entry "${archive_path}" "lib/libpid0.so.${release_version}"
    assert_archive_has_entry "${archive_path}" "lib/cmake/pid0/pid0Targets.cmake"
    assert_archive_has_entry "${archive_path}" "lib/cmake/pid0/pid0Targets-release.cmake"
    assert_archive_has_entry "${archive_path}" "share/libpid0/LICENSE"
    assert_archive_has_entry "${archive_path}" "share/libpid0/README.md"
    assert_archive_symlink "${archive_path}" "lib/libpid0.so" "libpid0.so.0"
    assert_archive_symlink "${archive_path}" "lib/libpid0.so.0" "libpid0.so.${release_version}"
    assert_archive_root_owned "${archive_path}"
  done
}

variant="${1:-all}"

write_checksums() {
  local -a artifacts=()
  local first_archive=""
  local release_version=""
  local checksum_file=""

  while IFS= read -r first_archive; do
    artifacts+=("${first_archive}")
  done < <(find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f -name 'libpid0-*.tar.gz' -printf '%f\n' | LC_ALL=C sort)

  if ((${#artifacts[@]} == 0)); then
    printf 'package.sh: no release archives found in %s\n' "${dist_dir}" >&2
    exit 1
  fi

  first_archive="${artifacts[0]}"
  release_version="${first_archive#libpid0-}"
  release_version="${release_version%%-linux-*}"
  checksum_file="libpid0-${release_version}-CHECKSUMS"

  if [[ -f "${dist_dir}/libpid0-${release_version}.h.gz" ]]; then
    artifacts+=("libpid0-${release_version}.h.gz")
  fi
  mapfile -t artifacts < <(printf '%s\n' "${artifacts[@]}" | LC_ALL=C sort)

  (
    cd "${dist_dir}"
    sha256sum "${artifacts[@]}" > "${checksum_file}"
  )
}

mkdir -p "${dist_dir}"
find "${dist_dir}" -mindepth 1 -maxdepth 1 \( -name 'libpid0-*.tar.gz' -o -name 'libpid0-*.h' -o -name 'libpid0-*.h.gz' -o -name 'libpid0-*-CHECKSUMS' -o -name '_CPack_Packages' \) -exec rm -rf {} +

case "${variant}" in
  all)
    build_single_header
    build_one pkg-x86_64-musl
    build_one pkg-x86_64-gnu
    build_one pkg-aarch64-musl
    build_one pkg-aarch64-gnu
    build_one pkg-armhf-musl
    build_one pkg-armhf-gnu
    ;;
  musl)
    build_single_header
    build_one pkg-x86_64-musl
    build_one pkg-aarch64-musl
    build_one pkg-armhf-musl
    ;;
  gnu|glibc)
    build_single_header
    build_one pkg-x86_64-gnu
    build_one pkg-aarch64-gnu
    build_one pkg-armhf-gnu
    ;;
  *)
    printf 'usage: %s [all|musl|gnu]\n' "$0" >&2
    exit 2
    ;;
esac

validate_archives
write_checksums
