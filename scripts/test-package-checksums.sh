#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
tmp_root=$(mktemp -d /tmp/libpid0-package-checksums.XXXXXX)
trap 'rm -rf -- "$tmp_root"' EXIT

fail() {
  printf 'test-package-checksums.sh: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$tmp_root/dist"
: > "$tmp_root/dist/libpid0-0.4.2.tar.gz"
: > "$tmp_root/dist/libpid0-0.4.2-x86_64-linux-gnu.tar.gz"
: > "$tmp_root/dist/libpid0-0.4.2.h.gz"

cmake -DPID0_ROOT="$tmp_root" -DPID0_VERSION=0.4.2 \
  -P "$repo_root/cmake/package_checksums.cmake"

manifest="$tmp_root/dist/libpid0-0.4.2-CHECKSUMS"
[[ -f "$manifest" ]] || fail "checksum manifest was not generated"
for artifact in libpid0-0.4.2.tar.gz libpid0-0.4.2-x86_64-linux-gnu.tar.gz libpid0-0.4.2.h.gz; do
  awk '{ print $2 }' "$manifest" | grep -Fx "$artifact" >/dev/null ||
    fail "checksum manifest omitted $artifact"
done

printf 'test-package-checksums.sh: checksum manifest contract ok\n'
