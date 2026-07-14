#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/build"
touch "$tmp/bin/aarch64-linux-gcc" "$tmp/bin/aarch64-linux-readelf"; chmod +x "$tmp/bin/aarch64-linux-gcc" "$tmp/bin/aarch64-linux-readelf"
printf 'CMAKE_C_COMPILER:FILEPATH=%s\n' "$tmp/bin/aarch64-linux-gcc" > "$tmp/build/CMakeCache.txt"
"$root/scripts/discover_target_tools.sh" --build-dir "$tmp/build" --target-id aarch64-linux-gnu | grep -Fx "READELF=$tmp/bin/aarch64-linux-readelf" >/dev/null
printf 'CMAKE_READELF:FILEPATH=%s\n' "$tmp/bin/aarch64-linux-readelf" >> "$tmp/build/CMakeCache.txt"
"$root/scripts/discover_target_tools.sh" --build-dir "$tmp/build" --target-id aarch64-linux-gnu | grep -Fx "TARGET_ID=aarch64-linux-gnu" >/dev/null
cat > "$tmp/resolver" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ensure) exit 0 ;;
  discover) printf 'cc=%s\\nreadelf=%s\\n' "$tmp/bin/aarch64-linux-gcc" "$tmp/bin/aarch64-linux-readelf" ;;
esac
EOF
chmod +x "$tmp/resolver"
fallback_tools="$(CPKT_TOOLCHAIN_RESOLVER="$tmp/resolver" "$root/scripts/discover_target_tools.sh" --target-id aarch64-linux-gnu)"
grep -Fx "CC=$tmp/bin/aarch64-linux-gcc" <<<"$fallback_tools" >/dev/null
grep -Fx "READELF=$tmp/bin/aarch64-linux-readelf" <<<"$fallback_tools" >/dev/null
printf 'test-discover-target-tools.sh: ok\n'
