.DEFAULT_GOAL := help

.PHONY: vanilla
vanilla: ## Builds latest stable kernel, unpatched
	./scripts/build-kernel-wrapper

.PHONY: grsec
grsec: ## Builds grsecurity-patched kernel (requires credentials)
	GRSECURITY=1 ./scripts/build-kernel-wrapper

.PHONY: reprotest
reprotest: ## Builds simple kernel multiple times to confirm reproducibility
	./scripts/reproducibility-test

.PHONY: help
help: ## Prints this message and exits.
	@printf "Subcommands:\n\n"
	@perl -F':.*##\s+' -lanE '$$F[1] and say "\033[36m$$F[0]\033[0m : $$F[1]"' $(MAKEFILE_LIST) \
		| sort \
		| column -s ':' -t
