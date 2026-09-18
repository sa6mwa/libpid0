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

assert_compiler_runtime_paths() {
  local target=$1 description target_cc target_runtime_rpath runtime_library runtime_file runtime_dir
  local -a runtime_libraries=(libgcc_s.so.1 libstdc++.so.6)

  # This gate owns the complete collection contract, including fresh caches.
  # `discover` deliberately remains read-only, so provision before inspection.
  "$resolver" ensure "$target" >/dev/null
  description=$("$resolver" discover "$target")
  target_cc=$(value cc "$description")
  target_runtime_rpath=$(value runtime_rpath "$description")
  [[ -x "$target_cc" && -n "$target_runtime_rpath" ]] ||
    fail "resolver did not report compiler runtime paths for ${target}"
  if [[ "$target" == *-linux-gnu ]]; then
    runtime_libraries+=(libasan.so libubsan.so)
  fi
  for runtime_library in "${runtime_libraries[@]}"; do
    runtime_file=$("$target_cc" -print-file-name="$runtime_library")
    [[ -f "$runtime_file" ]] ||
      fail "${target} compiler did not report required runtime ${runtime_library}: ${runtime_file}"
    runtime_dir=$(dirname -- "$(realpath -e "$runtime_file")")
    case ":$target_runtime_rpath:" in
      *":$runtime_dir:"*) ;;
      *) fail "${target} resolver omitted compiler runtime directory ${runtime_dir}: ${target_runtime_rpath}" ;;
    esac
  done
}

description=$("$resolver" discover x86_64-linux-gnu)
cc=$(value cc "$description")
root=$(value root "$description")
sysroot=$(value sysroot "$description")
interpreter=$(value interpreter "$description")
runtime_rpath=$(value runtime_rpath "$description")
[[ -x "$cc" && -d "$root" && -d "$sysroot" && -x "$interpreter" && -n "$runtime_rpath" ]] ||
  fail 'resolver did not report a complete native Bootlin collection'

case "$interpreter" in
  "$sysroot"/*) ;;
  *) fail "resolver selected an interpreter outside its sysroot: $interpreter" ;;
esac
[[ "$runtime_rpath" == *"$sysroot/lib"* && "$runtime_rpath" == *"$sysroot/usr/lib"* ]] ||
  fail "resolver did not report the complete Bootlin runtime search path: $runtime_rpath"
for target in \
  x86_64-linux-gnu \
  x86_64-linux-musl \
  aarch64-linux-gnu \
  aarch64-linux-musl \
  armhf-linux-gnu \
  armhf-linux-musl; do
  assert_compiler_runtime_paths "$target"
done

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
