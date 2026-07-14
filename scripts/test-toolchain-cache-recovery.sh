#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
resolver="${script_dir}/cpkt-toolchains.sh"
tmp_root=""

fail() {
  printf 'test-toolchain-cache-recovery.sh: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -z "${tmp_root}" ]] || rm -rf -- "${tmp_root}"
}
trap cleanup EXIT

main() {
  local cache_root=""
  local archive=""
  local fake_bin=""

  [[ -x "${resolver}" ]] || fail "missing resolver: ${resolver}"
  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/libpid0-toolchain-cache-recovery.XXXXXX")"
  cache_root="${tmp_root}/cache"
  archive="${cache_root}/archives/x86-64--glibc--stable-2025.08-1.tar.xz"
  fake_bin="${tmp_root}/bin"
  mkdir -p "$(dirname -- "${archive}")" "${fake_bin}"
  printf 'corrupt Bootlin archive\n' > "${archive}"
  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'download attempted\n' >> "$CPKT_TEST_DOWNLOAD_LOG"
output=""
while (($#)); do
  if [[ "$1" == "--output" ]]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
printf 'replacement archive with intentionally invalid checksum\n' > "$output"
EOF
  chmod +x "${fake_bin}/curl"

  if PATH="${fake_bin}:${PATH}" CPKT_TOOLCHAIN_CACHE="${cache_root}" \
    CPKT_TEST_DOWNLOAD_LOG="${tmp_root}/downloads.log" \
    "${resolver}" ensure x86_64-linux-gnu > "${tmp_root}/resolver.log" 2>&1; then
    fail "mocked invalid replacement unexpectedly passed verification"
  fi
  [[ -s "${tmp_root}/downloads.log" ]] ||
    fail "corrupt cached archive was not replaced through the download path"
  [[ ! -e "${archive}" ]] || fail "corrupt cached archive was not removed before replacement"
  grep -F 'checksum mismatch for x86-64--glibc--stable-2025.08-1.tar.xz' "${tmp_root}/resolver.log" >/dev/null ||
    fail "replacement archive was not checksum-verified"
  printf 'test-toolchain-cache-recovery.sh: corrupt cache recovery contract ok\n'
}

main "$@"
