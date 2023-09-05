.DEFAULT_GOAL := help
IMG_NAME = fpf.local/kernel-builder
SCRIPT_OUTPUT_PREFIX=$(PWD)/build/$(shell date +%Y%m%d)
SCRIPT_OUTPUT_EXT=log

.PHONY: vanilla
vanilla: OUT:=$(SCRIPT_OUTPUT_PREFIX)-vanilla.$(SCRIPT_OUTPUT_EXT)
vanilla: ## Builds latest stable kernel, unpatched
	LINUX_MAJOR_VERSION="5.15" \
		script \
		--command ./scripts/build-kernel-wrapper \
		--return \
		$(OUT)

.PHONY: grsec
grsec: OUT:=$(SCRIPT_OUTPUT_PREFIX)-grsec.$(SCRIPT_OUTPUT_EXT)
grsec: ## Builds grsecurity-patched kernel (requires credentials)
	GRSECURITY=1 \
		script \
		--command ./scripts/build-kernel-wrapper \
		--return \
		$(OUT)

.PHONY: reprotest
reprotest: ## Builds simple kernel multiple times to confirm reproducibility
	LINUX_MAJOR_VERSION="5.15" ./scripts/reproducibility-test

.PHONY: reprotest-sd
reprotest-sd: ## DEBUG Builds SD kernel config without grsec in CI
	GRSECURITY=0 LOCALVERSION="-securedrop" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-securedrop-5.15" \
		LINUX_LOCAL_PATCHES_PATH="$(PWD)/patches" \
		./scripts/reproducibility-test

securedrop-core-5.15: OUT:=$(SCRIPT_OUTPUT_PREFIX)-securedrop-core-5.15.$(SCRIPT_OUTPUT_EXT)
securedrop-core-5.15: ## Builds kernels for SecureDrop servers, 5.15.x
	GRSECURITY=1 GRSECURITY_PATCH_TYPE=stable6 LOCALVERSION="-securedrop" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-securedrop-5.15" \
		LINUX_LOCAL_PATCHES_PATH="$(PWD)/patches" \
		script \
		--command ./scripts/build-kernel-wrapper \
		--return \
		$(OUT)

securedrop-workstation-5.15: OUT:=$(SCRIPT_OUTPUT_PREFIX)-securedrop-workstation-5.15.$(SCRIPT_OUTPUT_EXT)
securedrop-workstation-5.15: ## Builds kernels for SecureDrop Workstation, 5.15.x
	GRSECURITY=1 GRSECURITY_PATCH_TYPE=stable6 LOCALVERSION="-workstation" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-workstation-5.15" \
		script \
		--command ./scripts/build-kernel-wrapper \
		--return \
		$(OUT)

.PHONY: help
help: ## Prints this message and exits.
	@printf "Subcommands:\n\n"
	@perl -F':.*##\s+' -lanE '$$F[1] and say "\033[36m$$F[0]\033[0m : $$F[1]"' $(MAKEFILE_LIST) \
		| sort \
		| column -s ':' -t
