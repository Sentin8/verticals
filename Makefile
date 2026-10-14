# SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
# SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
# SPDX-FileCopyrightText: Copyright Contributors to the Sentin8
# SPDX-License-Identifier: Apache-2.0

# sentin8.new — aggregation root (RS §7.3, grouped layout §4.4)
#
# Optional orchestration across the seven GROUP folders. This is the only
# place that builds the whole tree; individual teams build their own repo
# alone (the SDK git pin carries everything else). Group folders have
# their own Makefiles for group-scoped work; this file delegates.
#
# Build order is the repo DAG (RS §2.5): platform SDK -> starters ->
# services -> vertical SDKs -> vertical services. Dev infra is owned by
# the sentin8/ group (§2.2.1) — `infra-up` delegates there.

SHELL := /bin/bash

VERTICALS := bank8 hotel8 trade8 bill8 email8 exchange8

.PHONY: help build build-platform build-verticals infra-up infra-down status

help: ## Show this help
	@echo "sentin8.new aggregation (grouped layout, RS 4.4)"
	@echo ""
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

build: build-platform build-verticals ## Build the whole tree (DAG order)

build-platform: ## Build the sentin8/ group (SDK -> starters -> 17 services)
	@$(MAKE) -C sentin8 build

build-verticals: build-platform ## Build every vertical group (sdk -> services)
	@for v in $(VERTICALS); do \
		echo "=== $$v/ ==="; \
		$(MAKE) -C $$v build || exit 1; \
	done

infra-up: ## Start dev PG 18 + Valkey (owned by sentin8/, §2.2.1)
	@$(MAKE) -C sentin8 infra-up

infra-down: ## Stop the dev infra
	@$(MAKE) -C sentin8 infra-down

status: ## Per-group repo HEADs
	@for g in sentin8 $(VERTICALS); do \
		echo "── $$g/"; \
		for d in $$g/*/; do \
			[ -d "$$d/.git" ] || continue; \
			printf "  %-24s %s\n" "$$(basename $$d)" "$$(git -C $$d log --oneline -1 2>/dev/null | head -c 56)"; \
		done; \
	done