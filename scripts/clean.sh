#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

for path in "${repo_root}/build" "${repo_root}/dist" "${repo_root}/.cache" "${repo_root}/scripts/__pycache__"; do
  case "${path}" in
    "${repo_root}/build"|\
    "${repo_root}/dist"|\
    "${repo_root}/.cache"|\
    "${repo_root}/scripts/__pycache__")
      rm -rf -- "${path}"
      ;;
    *)
      printf 'clean.sh: refusing unsafe generated path: %s\n' "${path}" >&2
      exit 1
      ;;
  esac
done
