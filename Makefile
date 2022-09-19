.DEFAULT_GOAL := help
IMG_NAME = fpf.local/kernel-builder

.PHONY: vanilla
vanilla: ## Builds latest stable kernel, unpatched
	./scripts/build-kernel-wrapper

.PHONY: grsec
grsec: ## Builds grsecurity-patched kernel (requires credentials)
	GRSECURITY=1 ./scripts/build-kernel-wrapper

.PHONY: reprotest
reprotest: ## Builds simple kernel multiple times to confirm reproducibility
	./scripts/reproducibility-test

.PHONY: reprotest-sd
reprotest-sd: ## DEBUG Builds SD kernel config without grsec in CI
	GRSECURITY=0 LOCALVERSION="-securedrop" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-securedrop-5.15" \
		LINUX_LOCAL_PATCHES_PATH="$(PWD)/patches" \
		./scripts/reproducibility-test

securedrop-core-5.15: ## Builds kernels for SecureDrop servers, 5.15.x
	GRSECURITY=1 GRSECURITY_PATCH_TYPE=stable6 LOCALVERSION="-securedrop" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-securedrop-5.15" \
		LINUX_LOCAL_PATCHES_PATH="$(PWD)/patches" \
		./scripts/build-kernel-wrapper

securedrop-workstation-5.15: ## Builds kernels for SecureDrop Workstation, 5.15.x
	GRSECURITY=1 GRSECURITY_PATCH_TYPE=stable6 LOCALVERSION="-workstation" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-workstation-5.15" \
		./scripts/build-kernel-wrapper

.PHONY: help
help: ## Prints this message and exits.
	@printf "Subcommands:\n\n"
	@perl -F':.*##\s+' -lanE '$$F[1] and say "\033[36m$$F[0]\033[0m : $$F[1]"' $(MAKEFILE_LIST) \
		| sort \
		| column -s ':' -t
