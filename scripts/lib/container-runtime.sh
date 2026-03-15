#!/usr/bin/env bash

pid0_container_runtime() {
  local candidate

  for candidate in nerdctl podman docker; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

pid0_require_container_runtime() {
  local runtime

  if ! runtime="$(pid0_container_runtime)"; then
    printf 'pid0: no supported container runtime found (checked nerdctl, podman, docker)\n' >&2
    return 1
  fi

  printf '%s\n' "${runtime}"
}
