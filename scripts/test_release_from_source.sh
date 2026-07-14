#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
dist_dir="${repo_root}/dist"
tmp_root=""

cleanup() {
  if [[ -n "${tmp_root}" ]]; then
    rm -rf -- "${tmp_root}"
  fi
}
trap cleanup EXIT

checksum_file="$(find "${dist_dir}" -mindepth 1 -maxdepth 1 -type f -name 'libpid0-*-CHECKSUMS' -print | LC_ALL=C sort | head -n 1)"
if [[ -z "${checksum_file}" ]]; then
  printf 'test_release_from_source.sh: no checksum manifest found in %s\n' "${dist_dir}" >&2
  exit 1
fi

source_artifact="$(awk '{ print $2 }' "${checksum_file}" | grep -E '^libpid0-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz$' || true)"
if [[ -z "${source_artifact}" ]]; then
  printf 'test_release_from_source.sh: checksum manifest does not list source archive\n' >&2
  exit 1
fi

version="${source_artifact#libpid0-}"
version="${version%.tar.gz}"
tmp_root="$(mktemp -d "${dist_dir}/.source-smoke.XXXXXX")"
tar -xzf "${dist_dir}/${source_artifact}" -C "${tmp_root}"
source_root="${tmp_root}/libpid0-${version}"

(
  cd "${source_root}"
  find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort
) > "${tmp_root}/source-archive-files"
cmp -s "${source_root}/RELEASE_MANIFEST" "${tmp_root}/source-archive-files" || {
  printf 'test_release_from_source.sh: source archive payload does not exactly match RELEASE_MANIFEST\n' >&2
  exit 1
}

(
  cd "${source_root}"
  cmake --fresh --preset debug >/dev/null
  cmake --build --preset debug >/dev/null
  ctest --preset debug
)

configured_version="$(awk -F= '$1 ~ "^CMAKE_PROJECT_VERSION:" { print $2; exit }' "${source_root}/build/debug/CMakeCache.txt")"
if [[ "${configured_version}" != "${version}" ]]; then
  printf 'test_release_from_source.sh: configured version %s != archive version %s\n' "${configured_version}" "${version}" >&2
  exit 1
fi

printf 'test_release_from_source.sh: source archive smoke ok\n'
