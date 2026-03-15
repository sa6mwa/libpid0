#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"${script_dir}/container-build.sh"

# shellcheck source=scripts/lib/container-runtime.sh
source "${script_dir}/lib/container-runtime.sh"

runtime="${PID0_CONTAINER_RUNTIME:-$(pid0_require_container_runtime)}"
image="${PID0_CONTAINER_IMAGE:-libpid0-example:latest}"
run_flags=(--rm)

if [[ -t 0 ]]; then
  run_flags+=(-i)
fi
if [[ -t 1 ]]; then
  run_flags+=(-t)
fi

exec "${runtime}" run "${run_flags[@]}" "${image}" "$@"
