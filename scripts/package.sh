#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
dist_dir="${repo_root}/dist"

target_presets=(
  x86_64-linux-musl-release
  x86_64-linux-gnu-release
  aarch64-linux-musl-release
  aarch64-linux-gnu-release
  armhf-linux-musl-release
  armhf-linux-gnu-release
)

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

release_version() {
  "${script_dir}/release_version.sh"
}

clean_dist() {
  mkdir -p "${dist_dir}"
  find "${dist_dir}" -mindepth 1 -maxdepth 1 \
    \( -name 'libpid0-*.tar.gz' -o -name 'libpid0-*.h' -o -name 'libpid0-*.h.gz' -o -name 'libpid0-*-CHECKSUMS' -o -name '_CPack_Packages' \) \
    -exec rm -rf {} +
}

build_single_header() {
  cmake --fresh --preset release
  cmake --build --preset release --target package-single-header
}

build_binary_sdk() {
  local configure_preset="$1"
  local build_dir="${repo_root}/build/${configure_preset}"
  local cache_path="${build_dir}/CMakeCache.txt"
  local version=""
  local target_id=""
  local archive_path=""
  local stage_dir=""
  local payload_root=""

  cmake --fresh --preset "${configure_preset}"
  cmake --build --preset "${configure_preset}"

  version="$(cache_value "${cache_path}" CMAKE_PROJECT_VERSION)"
  target_id="$(cache_value "${cache_path}" PID0_TARGET_ID)"
  archive_path="${dist_dir}/libpid0-${version}-${target_id}.tar.gz"
  stage_dir="$(mktemp -d "${dist_dir}/.stage.XXXXXX")"
  payload_root="${stage_dir}/libpid0-${version}-${target_id}"

  cmake --install "${build_dir}" --prefix "${payload_root}"
  (
    cd "${stage_dir}"
    tar --sort=name --owner=0 --group=0 --numeric-owner -czf "${archive_path}" "libpid0-${version}-${target_id}"
  )
  rm -rf "${stage_dir}"
}

stage_source_archive() {
  local version="$1"
  local stage_dir="$2"
  local payload_root="${stage_dir}/libpid0-${version}"
  local manifest_path="${payload_root}/RELEASE_MANIFEST"
  local file_path=""

  mkdir -p "${payload_root}"
  (
    cd "${repo_root}"
    git ls-files | LC_ALL=C sort
  ) > "${manifest_path}.tmp"

  while IFS= read -r file_path; do
    mkdir -p "${payload_root}/$(dirname -- "${file_path}")"
    cp -p "${repo_root}/${file_path}" "${payload_root}/${file_path}"
  done < "${manifest_path}.tmp"

  printf '%s\n' "VERSION" "RELEASE_MANIFEST" >> "${manifest_path}.tmp"
  LC_ALL=C sort -o "${manifest_path}.tmp" "${manifest_path}.tmp"
  mv "${manifest_path}.tmp" "${manifest_path}"
  printf '%s\n' "${version}" > "${payload_root}/VERSION"
}

build_source_archive() {
  local version="$1"
  local stage_dir=""
  local archive_path="${dist_dir}/libpid0-${version}.tar.gz"

  stage_dir="$(mktemp -d "${dist_dir}/.source.XXXXXX")"
  stage_source_archive "${version}" "${stage_dir}"
  (
    cd "${stage_dir}"
    tar --sort=name --owner=0 --group=0 --numeric-owner -czf "${archive_path}" "libpid0-${version}"
  )
  rm -rf "${stage_dir}"
}

write_checksums() {
  local version="$1"
  local checksum_file="libpid0-${version}-CHECKSUMS"
  local -a artifacts=()

  mapfile -t artifacts < <(
    find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f \
      \( -name "libpid0-${version}.tar.gz" -o -name "libpid0-${version}-*.tar.gz" -o -name "libpid0-${version}.h.gz" \) \
      -printf '%f\n' | LC_ALL=C sort
  )
  if ((${#artifacts[@]} == 0)); then
    printf 'package.sh: no release artifacts found in %s for %s\n' "${dist_dir}" "${version}" >&2
    exit 1
  fi

  (
    cd "${dist_dir}"
    sha256sum "${artifacts[@]}" > "${checksum_file}"
  )
}

selected_presets() {
  local variant="$1"
  local preset=""

  case "${variant}" in
    all)
      printf '%s\n' "${target_presets[@]}"
      ;;
    musl)
      for preset in "${target_presets[@]}"; do
        [[ "${preset}" == *-musl-release ]] && printf '%s\n' "${preset}"
      done
      ;;
    gnu|glibc)
      for preset in "${target_presets[@]}"; do
        [[ "${preset}" == *-gnu-release ]] && printf '%s\n' "${preset}"
      done
      ;;
    *)
      printf 'usage: %s [all|musl|gnu]\n' "$0" >&2
      exit 2
      ;;
  esac
}

main() {
  local variant="${1:-all}"
  local version=""
  local preset=""

  clean_dist
  version="$(release_version)"
  build_single_header
  build_source_archive "${version}"

  while IFS= read -r preset; do
    build_binary_sdk "${preset}"
  done < <(selected_presets "${variant}")

  write_checksums "${version}"
  "${script_dir}/package-verify.sh"
}

main "$@"
