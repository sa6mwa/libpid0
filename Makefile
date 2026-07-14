SHELL := bash
.DEFAULT_GOAL := help
MAKEFLAGS += --no-builtin-rules
.NOTPARALLEL:

DEV_PRESET := debug

.PHONY: help print-release-version configure deps-debug deps-release deps-cross build build-debug build-release build-host test test-debug test-host test-all test-configure-lock test-cmocka-configure test-dependency-cache test-optional-dependency-cache test-toolchain-cache-recovery test-package-privacy valgrind asan fuzz fuzz-smoke format package package-single-header package-source package-source-smoke package-checksums package-verify verify-release-archives verify-release-privacy test-install-tree release-matrix finalize-slice release-pipeline prerelease prerelease-hardening container-example container-smoke-test release clean clean-dist

help:
	@printf '%s\n' \
		'make configure      Configure the development preset.' \
		'make print-release-version Print the version packaging will use.' \
		'make deps-debug     Provision the pinned debug toolchain and test dependencies.' \
		'make deps-release   Provision the pinned native release toolchain.' \
		'make deps-cross     Provision the pinned cross-release toolchains.' \
		'make build          Build the development preset.' \
		'make build-debug    Build the debug preset.' \
		'make build-release  Build the release preset.' \
		'make build-host     Alias for build-release.' \
		'make test           Build and run the development test suite.' \
		'make test-debug     Build and run the debug test suite.' \
		'make test-host      Build and run the native release test suite.' \
		'make test-all       Run local lifecycle tests.' \
		'make test-configure-lock Verify configuration serialization per build directory.' \
		'make test-cmocka-configure Verify a clean cmocka configure and unit test.' \
		'make test-dependency-cache Verify shared dependency-cache behavior.' \
		'make test-optional-dependency-cache Verify dependency-free configuration needs no dependency cache.' \
		'make test-toolchain-cache-recovery Verify corrupt shared toolchain archives retry through download.' \
		'make test-package-privacy Verify cache paths are rejected from release artifacts.' \
		'make valgrind       Run native x86_64 Linux memory checks.' \
		'make asan           Build and run the ASan/UBSan preset.' \
		'make fuzz-smoke     Run a bounded native AFL++ timeout-parser fuzzing job.' \
		'make format         Run clang-format on repo C/header sources.' \
		'make package        Generate release artifacts.' \
		'make package-single-header Generate the single-header release artifact.' \
		'make package-source Generate release artifacts including the source archive.' \
		'make package-source-smoke Build and test from the source archive.' \
		'make package-checksums Generate the release checksum manifest.' \
		'make package-verify Verify checksum-listed release artifacts.' \
		'make test-install-tree Verify installed SDK consumers.' \
		'make verify-release-archives Alias for package-verify.' \
		'make verify-release-privacy Alias for package-verify.' \
		'make release-matrix Generate the Linux release target matrix.' \
		'make finalize-slice Format and run the narrow local gate.' \
		'make prerelease     Run the release proof graph without cleaning generated state.' \
		'make prerelease-hardening Alias for prerelease; no extra hardening surfaces exist.' \
		'make container-example Run the scratch-container example (ARGS="Alice").' \
		'make container-smoke-test Build and smoke-test the scratch-container example.' \
		'make release        Generate single-header and package release artifacts.' \
		'make clean          Remove build/ and dist/ generated artifacts.' \
		'make clean-dist     Remove dist/ release artifacts.'

print-release-version:
	./scripts/release_version.sh

deps-debug:
	./scripts/cpkt-toolchains.sh ensure x86_64-linux-gnu

deps-release:
	./scripts/cpkt-toolchains.sh ensure x86_64-linux-gnu

deps-cross:
	./scripts/cpkt-toolchains.sh ensure all

configure:
	./scripts/configure.sh $(DEV_PRESET)

build:
	cmake --preset $(DEV_PRESET)
	./scripts/build.sh $(DEV_PRESET)

build-debug: build

build-release:
	cmake --preset release
	./scripts/build.sh release

build-host: build-release

test: build
	./scripts/test.sh $(DEV_PRESET)

test-debug: test

test-host: build-host
	./scripts/test.sh release

test-all: test test-configure-lock test-cmocka-configure test-optional-dependency-cache test-toolchain-cache-recovery test-host asan valgrind fuzz-smoke test-dependency-cache test-package-privacy

test-configure-lock:
	./scripts/test-configure-lock.sh

test-cmocka-configure:
	./scripts/test-cmocka-configure.sh

test-dependency-cache:
	./scripts/test-dependency-cache.sh

test-optional-dependency-cache:
	./scripts/test-optional-dependency-cache.sh

test-toolchain-cache-recovery:
	./scripts/test-toolchain-cache-recovery.sh

test-package-privacy:
	./scripts/test-package-privacy.sh

valgrind:
	./scripts/valgrind.sh

asan:
	cmake --preset asan
	./scripts/build.sh asan
	./scripts/test.sh asan

fuzz:
	cmake --preset fuzz
	cmake --build --preset fuzz

fuzz-smoke: fuzz
	rm -rf build/fuzz/afl-out
	"$$(./scripts/cpkt-aflpp.sh discover | awk -F= '$$1 == "afl_fuzz" { print $$2 }')" -V 5 -i fuzz/seeds -o build/fuzz/afl-out -- build/fuzz/fuzz/pid0-stop-timeout-fuzz

format:
	cmake --preset $(DEV_PRESET)
	cmake --build --preset $(DEV_PRESET) --target format

package:
	./scripts/package.sh

package-single-header:
	cmake --preset release -DPID0_DIST_DIR="$(CURDIR)/dist"
	cmake --build --preset release --target package-single-header

package-source: package

package-source-smoke:
	./scripts/test_release_from_source.sh

package-checksums:
	cmake --preset release
	cmake --build --preset release --target package-checksums

package-verify:
	./scripts/package-verify.sh

test-install-tree: package-verify

verify-release-archives: package-verify

verify-release-privacy: package-verify

release-matrix: package

finalize-slice: format test

release-pipeline: format test-all release-matrix package-source-smoke

prerelease: release-pipeline

prerelease-hardening: prerelease

container-example:
	./scripts/container-run.sh $(ARGS)

container-smoke-test:
	./scripts/container-smoke-test.sh

release: clean release-pipeline

clean:
	./scripts/clean.sh

clean-dist:
	rm -rf dist
