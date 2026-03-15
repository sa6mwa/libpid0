#!/usr/bin/env bash
set -euo pipefail

build_dir="${1:-build/dev}"
shift || true

"${build_dir}/example/pid0-example" "$@"
