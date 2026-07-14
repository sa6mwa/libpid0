# libpid0

`libpid0` is a tiny Linux PID 1 helper for C programs that need to run as init
inside a `FROM scratch` container or as PID 1 on a bare VM.

If the current process is not PID 1, `pid0_run()` just calls your submain with
`argc`/`argv` and returns its exit code.

If the current process is PID 1, `pid0_run()`:

- forks a managed child process
- puts the child in its own process group
- forwards incoming signals to that child process group
- reaps adopted child processes
- sets the child's process group as the foreground group for `stdin`,
  `stdout`, and `stderr` when those file descriptors are TTYs
- exits with the managed child's exit status

## Public ABI

```c
#include <pid0/pid0.h>

static int submain(int argc, char **argv) {
  (void)argc;
  (void)argv;
  return 0;
}

int main(int argc, char **argv) {
  return pid0_run(submain, argc, argv);
}
```

## Configuration

`PID0_STOP_TIMEOUT` controls how long PID 1 waits after the first terminate-like
signal (`SIGTERM`, `SIGINT`, `SIGQUIT`, `SIGHUP`) before sending `SIGKILL` to
the child's process group.

Accepted formats:

- `30`
- `30s`
- `1m15s`
- `2h`

The default is `30s`.

## Build

```sh
./scripts/configure.sh debug
./scripts/build.sh debug
./scripts/test.sh debug
```

The same development workflow is also available through `make`:

```sh
make build
make test
make prerelease
```

Useful presets:

- `debug`
- `release`
- `asan`
- `static-release`
- `x86_64-linux-gnu-release`
- `x86_64-linux-musl-release`
- `aarch64-linux-gnu-release`
- `aarch64-linux-musl-release`
- `armhf-linux-gnu-release`
- `armhf-linux-musl-release`

Every Linux preset uses its matching checksum-pinned Bootlin GCC collection.
The lifecycle resolver caches complete compiler, linker, binutils, libc, and
headers under `${CPKT_TOOLCHAIN_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/c.pkt.systems/toolchains}`;
it never falls back to a host or distro compiler. `debug`, `release`, and
`valgrind` use the native `x86_64-linux-gnu` collection.

`static-release` is the preset used for the scratch-container example.

## Developer Tools

Format all tracked C/header sources with:

```sh
cmake --build --preset debug --target format
```

Inspect `dist/` as a tree while traversing `.tar.gz` artifacts virtually,
without extracting them:

```sh
./scripts/dist-tree.sh
```

## Example

The example app lives in `example/` and prints `Hello <name>!`, waits 10
seconds, and exits.

- default name: `World`
- positional argument: use it as the name
- `-i`: prompt on standard input for the name
- `PID0_EXAMPLE_SLEEP_SECONDS`: override the 10-second delay for smoke tests

Run it from the build tree:

```sh
./scripts/run-example.sh build/debug
./scripts/run-example.sh build/debug Alice
printf 'Alice\n' | ./scripts/run-example.sh build/debug -i
```

A single-header example is also built when examples are enabled:

```sh
cmake --build --preset debug --target pid0-single-header-example
PID0_EXAMPLE_SLEEP_SECONDS=0 build/debug/example/pid0-single-header-example Alice
```

`example/Containerfile` builds a static `musl` binary and copies it into a
`scratch` image.

Container scripts prefer `nerdctl`, then `podman`, then `docker`:

```sh
./scripts/container-build.sh
./scripts/container-run.sh Alice
./scripts/container-smoke-test.sh
```

`container-run.sh` automatically adds `-i` and `-t` when you launch it from an
interactive terminal, so `./scripts/container-run.sh -i` behaves like running
the selected runtime manually with `run -ti --rm`.

## Tests

The build produces both:

- `libpid0.so`
- `libpid0.a`

## Packaging

Packaging writes tarballs to `dist/` with explicit ABI suffixes.

Versioning rules:

- default version: `0.0.0`
- if `HEAD` is exactly tagged as `vX.Y.Z`, packages use `X.Y.Z`

Artifacts:

- `dist/libpid0-<version>.tar.gz`
- `dist/libpid0-<version>.h.gz`
- `dist/libpid0-<version>-x86_64-linux-musl.tar.gz`
- `dist/libpid0-<version>-x86_64-linux-gnu.tar.gz`
- `dist/libpid0-<version>-aarch64-linux-musl.tar.gz`
- `dist/libpid0-<version>-aarch64-linux-gnu.tar.gz`
- `dist/libpid0-<version>-armhf-linux-musl.tar.gz`
- `dist/libpid0-<version>-armhf-linux-gnu.tar.gz`
- `dist/libpid0-<version>-CHECKSUMS`

Build them with:

```sh
make release
```

`make release` is the local clean release gate. It removes generated state,
builds the release artifacts, writes `dist/libpid0-<version>-CHECKSUMS`,
verifies the checksum-listed artifacts, and smoke-tests the source archive.
`make prerelease` runs that same proof graph without the initial clean; use it
for iterative release-equivalent feedback.

`./scripts/package.sh` builds and verifies the full release matrix by default
from the pinned Bootlin collections:

- x86_64 musl
- x86_64 glibc
- aarch64 musl
- aarch64 glibc
- armhf musl
- armhf glibc

Darwin arm64 is not currently a release target. `libpid0` is a Linux PID 1
helper, and a Darwin artifact would need a separate product/runtime contract
plus Mach-O package verification before it could be lifecycle-valid.

You can also build subsets:

```sh
./scripts/package.sh musl
./scripts/package.sh gnu
```

After packaging, `dist/libpid0-<version>-CHECKSUMS` is generated with
`sha256sum` entries for the produced tarballs and gzipped single-header
artifact, using basenames only. The checksum manifest is the release upload
manifest.

Each platform package contains headers, `libpid0.a`, shared libraries, CMake
package metadata, pkg-config metadata, documentation, and the license under
`share/doc/libpid0/`. `lib/libpid0.so` is a symlink to `libpid0.so.0`, and
`lib/libpid0.so.0` is a symlink to the versioned shared library.

Useful lifecycle gates:

```sh
make valgrind
make package-verify
make package-source-smoke
make print-release-version
```

The test suite uses the checksum-pinned upstream `cmocka` 2.0.2 archive. It is
verified and shared under `${CPKT_DEPENDENCY_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/c.pkt.systems/deps}`;
extraction and build state remain disposable under `.cache/`.

Some PID namespace integration tests require `unshare` with sufficient kernel
permissions. When that is not available, those tests are skipped instead of
failing.

The container smoke test also skips cleanly when no supported container runtime
is available or when the selected runtime is not usable.
