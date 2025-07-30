GIT_ROOT ?= $(shell git rev-parse --show-toplevel)

build:
	uv run build

check: types lint

clean:
	rm -rf dist site .cache .ruff_cache .pytest_cache

fix: fix-markdown fix-python

fix-markdown:
	pnpm run fix:markdown

fix-python:
	uv run ruff check --fix

format: format-markdown format-python format-toml

format-markdown:
	pnpm run format:markdown

format-python:
	uv run ruff format

format-toml:
	pnpm run format:toml

lint: lint-markdown lint-python

lint-markdown:
	pnpm run lint:markdown

lint-python:
	uv run ruff check

pre-commit:
	uv run pre-commit run

pre-commit-all:
	uv run pre-commit run --all-files

sync:
	uv sync --all-extras --all-groups

test:
	uv run pytest --cov-branch --cov-report=term-missing --cov-report=lcov tests

types:
	uv run pyright
