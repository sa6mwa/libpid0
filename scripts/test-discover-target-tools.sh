#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "${root}/build"
tmp=$(mktemp -d "${root}/build/test-discover-target-tools.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/build" "$tmp/sysroot/lib" "$tmp/sysroot/usr/lib"
touch "$tmp/bin/aarch64-linux-gcc" "$tmp/bin/aarch64-linux-readelf"; chmod +x "$tmp/bin/aarch64-linux-gcc" "$tmp/bin/aarch64-linux-readelf"
touch "$tmp/sysroot/lib/ld-linux-aarch64.so.1"; chmod +x "$tmp/sysroot/lib/ld-linux-aarch64.so.1"
printf 'CMAKE_C_COMPILER:FILEPATH=%s\nPID0_BOOTLIN_ELF_INTERPRETER:FILEPATH=%s\nPID0_BOOTLIN_RUNTIME_RPATH:STRING=%s\n' \
  "$tmp/bin/aarch64-linux-gcc" "$tmp/sysroot/lib/ld-linux-aarch64.so.1" \
  "$tmp/sysroot/lib:$tmp/sysroot/usr/lib" > "$tmp/build/CMakeCache.txt"
"$root/scripts/discover_target_tools.sh" --build-dir "$tmp/build" --target-id aarch64-linux-gnu | grep -Fx "READELF=$tmp/bin/aarch64-linux-readelf" >/dev/null
printf 'CMAKE_READELF:FILEPATH=%s\n' "$tmp/bin/aarch64-linux-readelf" >> "$tmp/build/CMakeCache.txt"
"$root/scripts/discover_target_tools.sh" --build-dir "$tmp/build" --target-id aarch64-linux-gnu | grep -Fx "TARGET_ID=aarch64-linux-gnu" >/dev/null
cat > "$tmp/resolver" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ensure) exit 0 ;;
  discover) printf 'cc=%s\\nreadelf=%s\\ninterpreter=%s\\nruntime_rpath=%s\\n' \
    "$tmp/bin/aarch64-linux-gcc" "$tmp/bin/aarch64-linux-readelf" \
    "$tmp/sysroot/lib/ld-linux-aarch64.so.1" "$tmp/sysroot/lib:$tmp/sysroot/usr/lib" ;;
esac
EOF
chmod +x "$tmp/resolver"
fallback_tools="$(CPKT_TOOLCHAIN_RESOLVER="$tmp/resolver" "$root/scripts/discover_target_tools.sh" --target-id aarch64-linux-gnu)"
grep -Fx "CC=$tmp/bin/aarch64-linux-gcc" <<<"$fallback_tools" >/dev/null
grep -Fx "READELF=$tmp/bin/aarch64-linux-readelf" <<<"$fallback_tools" >/dev/null
grep -Fx "INTERPRETER=$tmp/sysroot/lib/ld-linux-aarch64.so.1" <<<"$fallback_tools" >/dev/null
grep -Fx "RUNTIME_RPATH=$tmp/sysroot/lib:$tmp/sysroot/usr/lib" <<<"$fallback_tools" >/dev/null
printf 'test-discover-target-tools.sh: ok\n'
