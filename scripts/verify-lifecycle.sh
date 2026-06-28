#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
presets_path="${repo_root}/CMakePresets.json"

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
  release \
  asan \
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

printf 'verify-lifecycle.sh: lifecycle preset contract ok\n'
