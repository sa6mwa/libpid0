SHELL := bash
.DEFAULT_GOAL := help
MAKEFLAGS += --no-builtin-rules

DEV_PRESET := dev

.PHONY: help configure build test format container-example container-smoke-test release clean clean-dist

help:
	@printf '%s\n' \
		'make configure      Configure the development preset.' \
		'make build          Build the development preset.' \
		'make test           Build and run the development test suite.' \
		'make format         Run clang-format on repo C/header sources.' \
		'make container-example Run the scratch-container example (ARGS="Alice").' \
		'make container-smoke-test Build and smoke-test the scratch-container example.' \
		'make release        Generate single-header and package release artifacts.' \
		'make clean          Remove build/ and dist/ generated artifacts.' \
		'make clean-dist     Remove dist/ release artifacts.'

configure:
	./scripts/configure.sh $(DEV_PRESET)

build:
	cmake --preset $(DEV_PRESET)
	./scripts/build.sh $(DEV_PRESET)

test: build
	./scripts/test.sh $(DEV_PRESET)

format:
	cmake --preset $(DEV_PRESET)
	cmake --build --preset $(DEV_PRESET) --target format

container-example:
	./scripts/container-run.sh $(ARGS)

container-smoke-test:
	./scripts/container-smoke-test.sh

release:
	./scripts/package.sh

clean:
	rm -rf build dist

clean-dist:
	rm -rf dist
