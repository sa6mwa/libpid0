#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/container-runtime.sh
source "${script_dir}/lib/container-runtime.sh"

if ! runtime="$(pid0_container_runtime)"; then
  exit 77
fi

if ! "${runtime}" info >/dev/null 2>&1; then
  exit 77
fi

image="libpid0-example:smoke-$$"
cleanup() {
  "${runtime}" rmi -f "${image}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

PID0_CONTAINER_RUNTIME="${runtime}" PID0_CONTAINER_IMAGE="${image}" \
  "${script_dir}/container-build.sh" >/dev/null

default_output="$("${runtime}" run --rm -e PID0_EXAMPLE_SLEEP_SECONDS=0 "${image}")"
if [[ "${default_output}" != *"Hello World!"* ]]; then
  printf 'pid0: expected default container output to contain "Hello World!", got:\n%s\n' "${default_output}" >&2
  exit 1
fi

interactive_output="$(printf 'Alice\n' | "${runtime}" run --rm -i -e PID0_EXAMPLE_SLEEP_SECONDS=0 "${image}" -i)"
if [[ "${interactive_output}" != *"Hello Alice!"* ]]; then
  printf 'pid0: expected interactive container output to contain "Hello Alice!", got:\n%s\n' "${interactive_output}" >&2
  exit 1
fi
