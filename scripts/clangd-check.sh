#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
compile_commands_dir="${repo_root}/build/debug"
output=""

fail() {
  printf 'clangd-check.sh: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${output}" ]] || rm -f -- "${output}"
}
trap cleanup EXIT

command -v clangd >/dev/null 2>&1 ||
  fail 'clangd is required for native editor diagnostics; install it on the development host'
[[ -f "${compile_commands_dir}/compile_commands.json" ]] ||
  fail "missing native debug compile database: ${compile_commands_dir}/compile_commands.json"

mapfile -t sources < <(sed -n 's/^[[:space:]]*"file": "\(.*\)"[,]*$/\1/p' \
  "${compile_commands_dir}/compile_commands.json" | awk -v root="${repo_root}/" \
  'index($0, root) == 1' | LC_ALL=C sort -u)
((${#sources[@]} > 0)) || fail 'native debug compile database has no source entries'
mkdir -p "${repo_root}/build"
for source in "${sources[@]}"; do
  output="$(mktemp "${repo_root}/build/clangd-check.XXXXXX")"
  # clangd --check also exercises optional code actions. They are not diagnostics.
  if ! clangd --tweaks= --compile-commands-dir="${compile_commands_dir}" --check="${source}" \
    >"${output}" 2>&1; then
    cat "${output}" >&2
    fail "native editor diagnostics failed for ${source}"
  fi
  rm -f "${output}"
  output=""
done

printf 'clangd-check.sh: native debug diagnostics ok\n'
