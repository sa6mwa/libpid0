SHELL := bash
.DEFAULT_GOAL := help
MAKEFLAGS += --no-builtin-rules

DEV_PRESET := debug

.PHONY: help print-release-version configure deps-debug deps-release deps-cross build build-debug build-release build-host test test-debug test-host test-all asan format package package-source package-source-smoke package-checksums package-verify verify-release-archives verify-release-privacy release-matrix finalize-slice prerelease prerelease-hardening container-example container-smoke-test release clean clean-dist

help:
	@printf '%s\n' \
		'make configure      Configure the development preset.' \
		'make print-release-version Print the version packaging will use.' \
		'make deps-debug     No-op: debug dependencies are resolved by CMake.' \
		'make deps-release   No-op: release dependencies are resolved by CMake/toolchains.' \
		'make deps-cross     No-op: cross toolchains must already be installed.' \
		'make build          Build the development preset.' \
		'make build-debug    Build the debug preset.' \
		'make build-release  Build the release preset.' \
		'make build-host     Alias for build-release.' \
		'make test           Build and run the development test suite.' \
		'make test-debug     Build and run the debug test suite.' \
		'make test-host      Alias for test-debug.' \
		'make test-all       Run local lifecycle tests.' \
		'make asan           Build and run the ASan/UBSan preset.' \
		'make format         Run clang-format on repo C/header sources.' \
		'make package        Generate release artifacts.' \
		'make package-source Generate release artifacts including the source archive.' \
		'make package-source-smoke Build and test from the source archive.' \
		'make package-checksums Generate the release checksum manifest.' \
		'make package-verify Verify checksum-listed release artifacts.' \
		'make verify-release-archives Alias for package-verify.' \
		'make verify-release-privacy Alias for package-verify.' \
		'make release-matrix Generate the Linux release target matrix.' \
		'make finalize-slice Format and run the narrow local gate.' \
		'make prerelease     Run deterministic local prerelease checks.' \
		'make prerelease-hardening Run prerelease plus release matrix.' \
		'make container-example Run the scratch-container example (ARGS="Alice").' \
		'make container-smoke-test Build and smoke-test the scratch-container example.' \
		'make release        Generate single-header and package release artifacts.' \
		'make clean          Remove build/ and dist/ generated artifacts.' \
		'make clean-dist     Remove dist/ release artifacts.'

print-release-version:
	./scripts/release_version.sh

deps-debug:
	@printf '%s\n' 'libpid0: debug dependencies are resolved by CMake.'

deps-release:
	@printf '%s\n' 'libpid0: release dependencies are resolved by CMake/toolchains.'

deps-cross:
	@printf '%s\n' 'libpid0: cross toolchains must already be installed.'

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

test-host: test-debug

test-all: test asan package package-source-smoke

asan:
	cmake --preset asan
	./scripts/build.sh asan
	./scripts/test.sh asan

format:
	cmake --preset $(DEV_PRESET)
	cmake --build --preset $(DEV_PRESET) --target format

package:
	./scripts/package.sh

package-source: package

package-source-smoke:
	./scripts/test_release_from_source.sh

package-checksums:
	cmake --preset release
	cmake --build --preset release --target package-checksums

package-verify:
	./scripts/package-verify.sh

verify-release-archives: package-verify

verify-release-privacy: package-verify

release-matrix: package

finalize-slice: format test

prerelease: test-all

prerelease-hardening: prerelease release-matrix

container-example:
	./scripts/container-run.sh $(ARGS)

container-smoke-test:
	./scripts/container-smoke-test.sh

release: clean package package-source-smoke

clean:
	./scripts/clean.sh

clean-dist:
	rm -rf dist
