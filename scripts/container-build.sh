#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

# shellcheck source=scripts/lib/container-runtime.sh
source "${script_dir}/lib/container-runtime.sh"

runtime="${PID0_CONTAINER_RUNTIME:-$(pid0_require_container_runtime)}"
image="${PID0_CONTAINER_IMAGE:-libpid0-example:latest}"

exec "${runtime}" build \
  -t "${image}" \
  -f "${repo_root}/example/Containerfile" \
  "${repo_root}"
