# Convenience wrapper around the common actions. `make help` lists them.
.DEFAULT_GOAL := help
.PHONY: help deps run test release docker-build docker-run compose-up compose-down

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

deps: ## Fetch dependencies
	mix deps.get

run: ## Run the relay in the foreground (dev): ws://127.0.0.1:4000/ws
	mix run --no-halt

test: ## Run the test suite
	mix test

release: ## Build a self-contained prod OTP release under _build/prod/rel/server
	MIX_ENV=prod mix release

docker-build: ## Build the Docker image (pokepals-relay:latest)
	docker build -t pokepals-relay:latest .

docker-run: ## Run the Docker image, publishing :4000
	docker run --rm -p 4000:4000 -e PORT=4000 pokepals-relay:latest

compose-up: ## Build + start via docker compose (detached)
	docker compose up -d --build

compose-down: ## Stop the docker compose stack
	docker compose down
