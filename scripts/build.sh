#!/usr/bin/env bash
set -euo pipefail

preset="${1:-debug}"

cmake --build --preset "${preset}"
