#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
resolver="$script_dir/cpkt-aflpp.sh"

fail() {
  printf 'test-aflpp-resolver.sh: %s\n' "$*" >&2
  exit 1
}

[[ -x "$resolver" ]] || fail "resolver is not executable"
bash -n "$resolver"
grep -Fq 'version=5.02c' "$resolver" || fail 'AFL++ version is not pinned'
grep -Fq 'archive_sha256=' "$resolver" || fail 'AFL++ checksum is not pinned'
grep -Fq 'cpkt-toolchains.sh' "$resolver" || fail 'resolver does not use the embedded Bootlin resolver'
grep -Fq 'install_cleanup_trap -rf "$tmp"' "$resolver" || fail 'resolver does not clean failed staging state'
grep -Fq 'CPKT_TOOLCHAIN_LOCK_TIMEOUT:-600' "$resolver" ||
  fail 'AFL++ cache lock does not use the lifecycle timeout'
grep -Fq 'collection_id()' "$resolver" ||
  fail 'AFL++ cache root is not keyed by Bootlin collection identity'
grep -Fq '.cpkt-aflpp-revision-$revision-$id' "$resolver" ||
  fail 'AFL++ readiness marker is not collection-specific'
grep -Fq 'with_cache_lock "$c/locks/aflplusplus-${version}-x86_64-linux-gnu.lock" ensure_locked' "$resolver" ||
  fail 'AFL++ root publication is not serialized'
grep -Fq 'ready "$r" "$id" && return' "$resolver" ||
  fail 'AFL++ readiness is not rechecked under the lock'
grep -Fq '"-DAFL_PATH=\"$helper\""' "$resolver" ||
  fail 'AFL++ cache paths are not preserved as one compiler argument'

fake_bin=$(mktemp -d /tmp/libpid0-aflpp-resolver.XXXXXX)
trap 'rm -rf -- "$fake_bin"' EXIT
printf '#!/usr/bin/env bash\nprintf "aarch64\\n"\n' > "$fake_bin/uname"
chmod +x "$fake_bin/uname"
if PATH="$fake_bin:$PATH" "$resolver" ensure >/dev/null 2>&1; then
  fail 'resolver accepted a non-native host'
fi

if env -u HOME -u XDG_CACHE_HOME -u CPKT_TOOLCHAIN_CACHE "$resolver" discover >/dev/null 2>&1; then
  fail 'resolver accepted a missing cache root'
fi

if "$resolver" ensure extra >/dev/null 2>&1; then
  fail 'resolver accepted an invalid command shape'
fi

printf 'test-aflpp-resolver.sh: AFL++ resolver contract ok\n'
