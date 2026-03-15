#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
dist_dir="${repo_root}/dist"

build_one() {
  local configure_preset="$1"
  local package_preset="$2"

  cmake --fresh --preset "${configure_preset}"
  cmake --build --preset "${configure_preset}"
  cpack --preset "${package_preset}"
  rm -rf "${dist_dir}/_CPack_Packages"
}

variant="${1:-all}"

write_checksums() {
  local -a archives=()
  local first_archive=""
  local release_version=""
  local checksum_file=""

  while IFS= read -r first_archive; do
    archives+=("${first_archive}")
  done < <(find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f -name 'libpid0-*.tar.gz' -printf '%f\n' | LC_ALL=C sort)

  if ((${#archives[@]} == 0)); then
    printf 'package.sh: no release archives found in %s\n' "${dist_dir}" >&2
    exit 1
  fi

  first_archive="${archives[0]}"
  release_version="${first_archive#libpid0-}"
  release_version="${release_version%%-linux-*}"
  checksum_file="libpid0-${release_version}-CHECKSUMS"

  (
    cd "${dist_dir}"
    sha256sum "${archives[@]}" > "${checksum_file}"
  )
}

mkdir -p "${dist_dir}"
find "${dist_dir}" -mindepth 1 -maxdepth 1 \( -name 'libpid0-*.tar.gz' -o -name 'libpid0-*-CHECKSUMS' -o -name '_CPack_Packages' \) -exec rm -rf {} +

case "${variant}" in
  all)
    build_one pkg-x86_64-musl pkg-x86_64-musl
    build_one pkg-x86_64-gnu pkg-x86_64-gnu
    build_one pkg-aarch64-musl pkg-aarch64-musl
    build_one pkg-aarch64-gnu pkg-aarch64-gnu
    build_one pkg-armhf-musl pkg-armhf-musl
    build_one pkg-armhf-gnu pkg-armhf-gnu
    ;;
  musl)
    build_one pkg-x86_64-musl pkg-x86_64-musl
    build_one pkg-aarch64-musl pkg-aarch64-musl
    build_one pkg-armhf-musl pkg-armhf-musl
    ;;
  gnu|glibc)
    build_one pkg-x86_64-gnu pkg-x86_64-gnu
    build_one pkg-aarch64-gnu pkg-aarch64-gnu
    build_one pkg-armhf-gnu pkg-armhf-gnu
    ;;
  *)
    printf 'usage: %s [all|musl|gnu]\n' "$0" >&2
    exit 2
    ;;
esac

write_checksums
