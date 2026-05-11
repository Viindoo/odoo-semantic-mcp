.PHONY: dev lint typecheck test up down index migrate index-all server-setup

# Install runtime + dev dependencies via uv. Requires `uv` on PATH.
dev:
	uv sync --extra dev

lint:
	uv run ruff check .

typecheck:
	uv run mypy osm

test:
	uv run pytest -q

up:
	docker compose up -d

down:
	docker compose down

# Run the indexer against one or more addon roots.
# Usage: make index ADDONS="./tests/fixtures/odoo_ce_subset ./tests/fixtures/custom_addons" TENANT=public GIT_SHA=fixture0
ADDONS ?=
TENANT ?= public
GIT_SHA ?= unknown
index:
	@if [ -z "$(ADDONS)" ]; then echo "error: ADDONS=<paths> required"; exit 2; fi
	uv run python scripts/index.py $(foreach p,$(ADDONS),--addons $(p)) --tenant $(TENANT) --git-sha $(GIT_SHA)

# Apply SQL migrations to the public schema. Override schema via:
#   make migrate SCHEMA=<tenant>
SCHEMA ?= public
migrate:
	uv run python scripts/migrate.py --schema $(SCHEMA)

# Index all three Odoo versions from the standard checkout paths.
# Requires ~/git/{17,18,19}.0/odoo to exist on the server machine.
# Usage: make index-all
ODOO_BASE ?= $(HOME)/git
index-all:
	@for v in 17 18 19; do \
	  SHA=$$(git -C "$(ODOO_BASE)/$${v}.0/odoo" rev-parse --short HEAD 2>/dev/null || echo unknown); \
	  echo "[index-all] Indexing v$${v} @ $${SHA}"; \
	  DATABASE_URL="postgresql:///osm_$${v}" uv run python scripts/index.py \
	    --addons "$(ODOO_BASE)/$${v}.0/odoo/odoo/addons" \
	    --addons "$(ODOO_BASE)/$${v}.0/odoo/addons" \
	    --tenant public --git-sha "$${SHA}"; \
	  echo "[index-all] v$${v} done"; \
	done

# Provision this machine as the osm server (runs server-setup.sh).
# Requires sudo. See scripts/server-setup.sh --help for options.
server-setup:
	bash scripts/server-setup.sh
