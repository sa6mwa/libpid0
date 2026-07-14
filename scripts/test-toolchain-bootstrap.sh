#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
resolver="$script_dir/cpkt-toolchains.sh"
toolchain_file="$script_dir/../cmake/toolchains/cpkt-linux.cmake"

fail() {
  printf 'test-toolchain-bootstrap.sh: %s\n' "$*" >&2
  exit 1
}

value() {
  sed -n "s/^$1=//p" <<<"$2" | tail -1
}

description=$("$resolver" discover x86_64-linux-gnu)
cc=$(value cc "$description")
root=$(value root "$description")
sysroot=$(value sysroot "$description")
[[ -x "$cc" && -d "$root" && -d "$sysroot" ]] ||
  fail 'resolver did not report a complete native Bootlin collection'

reported_ld=$("$cc" -print-prog-name=ld)
case "$reported_ld" in
  "$root"/*) ;;
  *) fail "compiler selected a linker outside its collection: $reported_ld" ;;
esac

reported_libc=$("$cc" "--sysroot=$sysroot" -print-file-name=libc.so)
[[ -e "$reported_libc" ]] ||
  fail "compiler did not report a usable libc: $reported_libc"
sysroot_real=$(realpath -e "$sysroot")
libc_real=$(realpath -e "$reported_libc")
case "$libc_real" in
  "$sysroot_real"/*) ;;
  *) fail "compiler selected a libc outside its sysroot: $libc_real" ;;
esac

grep -F -- '--sysroot=${pid0_sysroot}' "$toolchain_file" >/dev/null ||
  fail 'CMake bootstrap does not query libc through the selected sysroot'
grep -F 'Pinned compiler selected a libc outside its sysroot' "$toolchain_file" >/dev/null ||
  fail 'CMake bootstrap does not reject a libc outside the selected sysroot'

printf 'test-toolchain-bootstrap.sh: compiler collection integrity contract ok\n'
