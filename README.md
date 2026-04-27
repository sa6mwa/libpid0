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
./scripts/configure.sh dev
./scripts/build.sh dev
./scripts/test.sh dev
```

The same development workflow is also available through `make`:

```sh
make build
make test
make release
```

Useful presets:

- `dev`
- `release`
- `static-release`
- `musl-dev`
- `musl-release`
- `musl-static-release`
- `glibc-dev`
- `glibc-release`

`dev` and `release` prefer `musl-gcc` automatically and fall back to the system
compiler only when musl is unavailable.

`static-release` is the preset used for the scratch-container example.

## Developer Tools

Format all tracked C/header sources with:

```sh
cmake --build --preset dev --target format
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
./scripts/run-example.sh build/dev
./scripts/run-example.sh build/dev Alice
printf 'Alice\n' | ./scripts/run-example.sh build/dev -i
```

A single-header example is also built when examples are enabled:

```sh
cmake --build --preset dev --target pid0-single-header-example
PID0_EXAMPLE_SLEEP_SECONDS=0 build/dev/example/pid0-single-header-example Alice
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

- `dist/libpid0-<version>.h.gz`
- `dist/libpid0-<version>-linux-x86_64-musl.tar.gz`
- `dist/libpid0-<version>-linux-x86_64-gnu.tar.gz`
- `dist/libpid0-<version>-linux-aarch64-musl.tar.gz`
- `dist/libpid0-<version>-linux-aarch64-gnu.tar.gz`
- `dist/libpid0-<version>-linux-armhf-musl.tar.gz`
- `dist/libpid0-<version>-linux-armhf-gnu.tar.gz`
- `dist/libpid0-<version>-CHECKSUMS`

Build them with:

```sh
./scripts/package.sh
```

`make release` is an alias for `./scripts/package.sh`.

`./scripts/package.sh` builds the full release matrix by default:

- x86_64 musl via `musl-gcc`
- x86_64 glibc via the system `gcc`
- aarch64 musl via `aarch64-linux-musl-gcc`
- aarch64 glibc via `aarch64-linux-gnu-gcc`
- armhf musl via `arm-linux-musleabihf-gcc`
- armhf glibc via `arm-linux-gnueabihf-gcc`

You can also build subsets:

```sh
./scripts/package.sh musl
./scripts/package.sh gnu
```

After packaging, `dist/libpid0-<version>-CHECKSUMS` is generated with
`sha256sum` entries for the produced tarballs and gzipped single-header
artifact, using basenames only.

Each platform package contains headers, `libpid0.a`, shared libraries, CMake
package metadata, documentation, and the license. `lib/libpid0.so` is a symlink
to `libpid0.so.0`, and `lib/libpid0.so.0` is a symlink to the versioned shared
library.

The test suite uses `cmocka` 2.x. The build first tries a system `cmocka`
installation and falls back to fetching `cmocka-2.0.2`.

Some PID namespace integration tests require `unshare` with sufficient kernel
permissions. When that is not available, those tests are skipped instead of
failing.

The container smoke test also skips cleanly when no supported container runtime
is available or when the selected runtime is not usable.
