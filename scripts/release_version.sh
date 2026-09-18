#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -P -- "${script_dir}/.." && pwd)"

if [[ -n "${PID0_VERSION_OVERRIDE:-}" ]]; then
  if [[ ! "${PID0_VERSION_OVERRIDE}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'release_version.sh: PID0_VERSION_OVERRIDE must match X.Y.Z\n' >&2
    exit 1
  fi
  printf '%s\n' "${PID0_VERSION_OVERRIDE}"
  exit 0
fi

git_root="$(git -C "${repo_root}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "${git_root}" ]]; then
  git_root="$(cd -P -- "${git_root}" && pwd)"
fi
if [[ "${git_root}" == "${repo_root}" ]]; then
  tag=""
  while IFS= read -r candidate; do
    [[ "${candidate}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || continue
    [[ "$(git -C "${repo_root}" cat-file -t "refs/tags/${candidate}")" == "commit" ]] || continue
    if [[ -n "${tag}" ]]; then
      printf 'release_version.sh: multiple exact lightweight release tags point at HEAD\n' >&2
      exit 1
    fi
    tag="${candidate}"
  done < <(git -C "${repo_root}" tag --points-at HEAD --list 'v*')
  if [[ -n "${tag}" ]]; then
    printf '%s\n' "${tag#v}"
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
  printf 'release_version.sh: source archive VERSION must match X.Y.Z\n' >&2
  exit 1
fi

printf '0.0.0\n'
