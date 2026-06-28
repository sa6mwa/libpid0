# Lifecycle Migration

This repository is being conformed to the pkt.systems C/CMake lifecycle.

## Current Slice

- Old package presets `pkg-<arch>-<libc>` were replaced with lifecycle target
  presets such as `x86_64-linux-musl-release`.
- Release target IDs now use `<arch>-<os>-<libc>`, for example
  `x86_64-linux-musl`.
- Binary SDK archives are staged under a single top-level root:
  `libpid0-<version>-<target-id>/`.
- Binary SDK archives now install `pid0Config.cmake` and
  `pid0ConfigVersion.cmake` for `find_package(pid0 CONFIG REQUIRED)`.
- Binary SDK archives now install relocatable `lib/pkgconfig/pid0.pc` metadata.
- The release pipeline now builds a source archive, single-header artifact,
  binary SDK matrix, checksum manifest, package verification, and source archive
  smoke test through `make release`.
- `make help` is the public command index for the lifecycle targets currently
  implemented.
- `make package-verify` verifies checksum-listed release artifacts, archive
  layout, local-path privacy, ELF runtime metadata, and install-tree CMake
  consumers.

## Darwin Decision

`arm64-apple-darwin` is intentionally not in the release matrix yet.

`libpid0` is a Linux PID 1 helper for containers and VMs. The current
implementation depends on Linux/POSIX process-supervision behavior and the
release artifacts are Linux shared/static SDKs. A Darwin artifact would need a
separate product/runtime contract before it could be lifecycle-valid. In
particular, Darwin container-image support would need proof that the target can
exercise equivalent PID 1 supervision semantics and package valid Mach-O
artifacts with verified install names, dependency paths, and rpaths.

## Remaining Lifecycle Work

- Add Darwin target support only if there is a real Darwin runtime/product
  contract for PID 1 behavior and Mach-O artifact verification.
- Add release-upload helper scripts that use the checksum manifest as the upload
  source.
