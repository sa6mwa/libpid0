#!/usr/bin/env bash
set -euo pipefail

die() { printf 'discover_target_tools: %s\n' "$*" >&2; exit 1; }
build_dir=""; target_id=""
while (($#)); do
  case "$1" in
    --build-dir) build_dir=${2:-}; shift 2;;
    --target-id) target_id=${2:-}; shift 2;;
    *) die "usage: $0 [--build-dir <dir>] --target-id <id>";;
  esac
done
[[ -n "$target_id" ]] || die 'target id is required'
resolver="${CPKT_TOOLCHAIN_RESOLVER:-$(cd -- "$(dirname -- "$0")" && pwd)/cpkt-toolchains.sh}"
cache="${build_dir:+${build_dir}/CMakeCache.txt}"
value() { awk -F= -v key="$1" '$1 ~ "^" key ":" { print $2; exit }' "$cache"; }
if [[ -n "$cache" && -f "$cache" ]]; then
  cc=$(value CMAKE_C_COMPILER); readelf=$(value CMAKE_READELF)
  if [[ -z "$readelf" || ! -x "$readelf" ]]; then
    compiler_dir=$(dirname -- "$cc"); compiler_name=$(basename -- "$cc")
    prefix=${compiler_name%-gcc}; prefix=${prefix%-clang}; prefix=${prefix%-cc}
    for candidate in "$compiler_dir/$prefix-readelf" "$compiler_dir/readelf"; do
      [[ -x "$candidate" ]] && { readelf=$candidate; break; }
    done
  fi
  if [[ -z "$readelf" || ! -x "$readelf" ]]; then
    readelf=$(command -v readelf || true)
  fi
else
  [[ -x "$resolver" ]] || die "missing lifecycle toolchain resolver: $resolver"
  "$resolver" ensure "$target_id" >/dev/null
  description=$("$resolver" discover "$target_id")
  cc=$(sed -n 's/^cc=//p' <<<"$description" | tail -1)
  readelf=$(sed -n 's/^readelf=//p' <<<"$description" | tail -1)
fi
[[ -n "${cc:-}" && -x "$cc" ]] || die "unable to discover compiler for $target_id${cache:+ from $cache}"
[[ -n "$readelf" && -x "$readelf" ]] || die "unable to discover readelf for $target_id${cache:+ from $cache}"
printf 'TARGET_ID=%s\nCC=%s\nREADELF=%s\n' "$target_id" "$cc" "$readelf"
