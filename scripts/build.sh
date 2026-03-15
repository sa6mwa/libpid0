#!/usr/bin/env bash
set -euo pipefail

preset="${1:-dev}"

cmake --build --preset "${preset}"
