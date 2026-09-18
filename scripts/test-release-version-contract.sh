#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
workspace_root="${repo_root}/build"
workspace=""
annotated_tag="v98.98.98"
lightweight_tag="v99.99.99"

fail() {
  printf 'test-release-version-contract.sh: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${workspace}" ]] || rm -rf -- "${workspace}"
}
trap cleanup EXIT

assert_version() {
  local root="$1"
  local expected="$2"
  local actual=""

  actual="$(env -u PID0_VERSION_OVERRIDE make --no-print-directory --silent -C "${root}" print-release-version)"
  [[ "${actual}" == "${expected}" ]] ||
    fail "Make resolved ${actual}, expected ${expected}"
}

assert_cmake_version() {
  local root="$1"
  local expected="$2"
  local build_dir="$3"
  local actual=""

  env -u PID0_VERSION_OVERRIDE cmake --fresh --preset debug -S "${root}" -B "${build_dir}" \
    -DPID0_BUILD_TESTS=OFF -DPID0_BUILD_EXAMPLES=OFF >/dev/null
  actual="$(awk -F= '$1 ~ "^CMAKE_PROJECT_VERSION:" { print $2; exit }' "${build_dir}/CMakeCache.txt")"
  [[ "${actual}" == "${expected}" ]] ||
    fail "CMake resolved ${actual}, expected ${expected}"
}

assert_override_version() {
  local root="$1"
  local expected='7.8.9'
  local build_dir="${workspace}/cmake-override"
  local actual=""

  actual="$(PID0_VERSION_OVERRIDE="${expected}" make --no-print-directory --silent -C "${root}" print-release-version)"
  [[ "${actual}" == "${expected}" ]] ||
    fail "Make release-candidate override resolved ${actual}, expected ${expected}"
  cmake --fresh --preset debug -S "${root}" -B "${build_dir}" \
    -DPID0_BUILD_TESTS=OFF -DPID0_BUILD_EXAMPLES=OFF -DPID0_VERSION_OVERRIDE="${expected}" >/dev/null
  actual="$(awk -F= '$1 ~ "^CMAKE_PROJECT_VERSION:" { print $2; exit }' "${build_dir}/CMakeCache.txt")"
  [[ "${actual}" == "${expected}" ]] ||
    fail "CMake release-candidate override resolved ${actual}, expected ${expected}"
}

exact_lightweight_tag() {
  local root="$1"
  local candidate=""

  while IFS= read -r candidate; do
    [[ "${candidate}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    [[ "$(git -C "${root}" cat-file -t "refs/tags/${candidate}")" == "commit" ]] || continue
    printf '%s\n' "${candidate}"
    return
  done < <(git -C "${root}" tag --points-at HEAD --list 'v*')
}

create_fixture_repository() {
  local fixture_root="${workspace}/tag-fixture"
  local file_path=""

  mkdir -p "${fixture_root}"
  while IFS= read -r file_path; do
    mkdir -p "${fixture_root}/$(dirname -- "${file_path}")"
    cp -p "${repo_root}/${file_path}" "${fixture_root}/${file_path}"
  done < <(git -C "${repo_root}" ls-files)
  git -C "${fixture_root}" init -q
  git -C "${fixture_root}" add .
  git -C "${fixture_root}" -c commit.gpgSign=false -c user.name='Lifecycle fixture' \
    -c user.email='lifecycle-fixture@example.invalid' commit -qm 'test: version fixture'
  printf '%s\n' "${fixture_root}"
}

assert_source_archive_version() {
  local fixture_root="$1"
  local archive_root="${workspace}/source-archive/libpid0-7.8.9"
  local build_dir="${workspace}/source-archive-build"
  local actual=""

  mkdir -p "${archive_root}"
  git -C "${fixture_root}" archive HEAD | tar -x -C "${archive_root}"
  printf '7.8.9\n' > "${archive_root}/VERSION"
  git -C "${workspace}" init -q
  git -C "${workspace}" add source-archive
  git -C "${workspace}" -c commit.gpgSign=false -c user.name='Lifecycle fixture' \
    -c user.email='lifecycle-fixture@example.invalid' commit -qm 'test: enclosing repository'
  assert_version "${archive_root}" '7.8.9'
  env -u PID0_VERSION_OVERRIDE cmake --fresh --preset debug -S "${archive_root}" -B "${build_dir}" \
    -DPID0_BUILD_TESTS=OFF -DPID0_BUILD_EXAMPLES=OFF >/dev/null
  actual="$(awk -F= '$1 ~ "^CMAKE_PROJECT_VERSION:" { print $2; exit }' "${build_dir}/CMakeCache.txt")"
  [[ "${actual}" == '7.8.9' ]] ||
    fail "source archive CMake resolved ${actual}, expected 7.8.9"
}

assert_invalid_source_archive_version_rejected() {
  local archive_root="$1"
  local build_dir="${workspace}/source-archive-invalid-build"
  local output_path="${workspace}/source-archive-invalid.log"

  printf 'not-a-release-version\n' > "${archive_root}/VERSION"
  if env -u PID0_VERSION_OVERRIDE make --no-print-directory --silent -C "${archive_root}" \
    print-release-version > "${output_path}" 2>&1; then
    fail 'Make accepted malformed source archive VERSION'
  fi
  grep -F 'source archive VERSION must match X.Y.Z' "${output_path}" >/dev/null ||
    fail 'Make did not diagnose malformed source archive VERSION'
  if env -u PID0_VERSION_OVERRIDE cmake --fresh --preset debug -S "${archive_root}" -B "${build_dir}" \
    -DPID0_BUILD_TESTS=OFF -DPID0_BUILD_EXAMPLES=OFF > "${output_path}" 2>&1; then
    fail 'CMake accepted malformed source archive VERSION'
  fi
  grep -F 'Unable to resolve release version' "${output_path}" >/dev/null ||
    fail 'CMake did not reject malformed source archive VERSION'
}

main() {
  local existing_tag=""
  local fixture_root=""

  git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    fail 'must run from a Git worktree'
  mkdir -p "${workspace_root}"
  workspace="$(mktemp -d "${workspace_root}/release-version-contract.XXXXXX")"
  existing_tag="$(exact_lightweight_tag "${repo_root}")"

  assert_override_version "${repo_root}"

  if [[ -n "${existing_tag}" ]]; then
    assert_version "${repo_root}" "${existing_tag#v}"
    assert_cmake_version "${repo_root}" "${existing_tag#v}" "${workspace}/cmake-exact"
  else
    assert_version "${repo_root}" '0.0.0'
    assert_cmake_version "${repo_root}" '0.0.0' "${workspace}/cmake-untagged"
  fi

  fixture_root="$(create_fixture_repository)"
  assert_source_archive_version "${fixture_root}"
  assert_invalid_source_archive_version_rejected "${workspace}/source-archive/libpid0-7.8.9"
  git -C "${fixture_root}" -c tag.gpgSign=false -c user.name='Lifecycle fixture' \
    -c user.email='lifecycle-fixture@example.invalid' \
    tag -a "${annotated_tag}" -m 'temporary lifecycle contract tag'
  [[ "$(git -C "${fixture_root}" cat-file -t "refs/tags/${annotated_tag}")" == 'tag' ]] ||
    fail 'temporary annotated tag was not created as a tag object'
  assert_version "${fixture_root}" '0.0.0'
  assert_cmake_version "${fixture_root}" '0.0.0' "${workspace}/cmake-annotated"
  git -C "${fixture_root}" tag -d "${annotated_tag}" >/dev/null
  git -C "${fixture_root}" -c tag.gpgSign=false tag "${lightweight_tag}"
  [[ "$(git -C "${fixture_root}" cat-file -t "refs/tags/${lightweight_tag}")" == 'commit' ]] ||
    fail 'temporary lightweight tag did not resolve directly to a commit'
  assert_version "${fixture_root}" '99.99.99'
  assert_cmake_version "${fixture_root}" '99.99.99' "${workspace}/cmake-lightweight"
  ln -s "${fixture_root}" "${workspace}/tag-fixture-link"
  assert_version "${workspace}/tag-fixture-link" '99.99.99'
  printf 'test-release-version-contract.sh: release-version contract ok\n'
}

main "$@"
