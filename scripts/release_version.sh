#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

if [[ -n "${PID0_VERSION_OVERRIDE:-}" ]]; then
  if [[ ! "${PID0_VERSION_OVERRIDE}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'release_version.sh: PID0_VERSION_OVERRIDE must match X.Y.Z\n' >&2
    exit 1
  fi
  printf '%s\n' "${PID0_VERSION_OVERRIDE}"
  exit 0
fi

if git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tag="$(git -C "${repo_root}" describe --tags --exact-match --match 'v[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null || true)"
  if [[ "${tag}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '0.0.0\n'
  fi
  exit 0
fi

if [[ -f "${repo_root}/VERSION" ]]; then
  version="$(tr -d '[:space:]' < "${repo_root}/VERSION")"
  if [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "${version}"
    exit 0
  fi
fi

printf '0.0.0\n'
