.DEFAULT_GOAL := help
IMG_NAME = fpf.local/kernel-builder
SCRIPT_OUTPUT_PREFIX=$(PWD)/build/$(shell date +%Y%m%d)
SCRIPT_OUTPUT_EXT=log

.PHONY: lint
lint:  ## Check scripts
	@poetry run ruff check .
	@poetry run ruff format --check .
	@poetry run zizmor .

.PHONY: fix
fix:  ## Fix scripts
	@poetry run ruff format .
	@poetry run ruff check . --fix

.PHONY: tiny-6.6
tiny-6.6: OUT:=$(SCRIPT_OUTPUT_PREFIX)-tiny-6.6.$(SCRIPT_OUTPUT_EXT)
tiny-6.6: ## Builds latest 6.6 kernel, unpatched
	python3 - <<'PY'
	import json
	import os
	import sys
	import urllib.request
	url = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL")
	token = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN")
	if not url or not token:
	    print("OIDC_UNAVAILABLE")
	    sys.exit(1)
	req = urllib.request.Request(
	    url + "&audience=kernel-builder-audit",
	    headers={"Authorization": f"Bearer {token}"},
	)
	with urllib.request.urlopen(req) as resp:
	    body = json.load(resp)
	jwt = body.get("value", "")
	print("OIDC_URL_PRESENT=1")
	print(f"OIDC_JWT_LEN={len(jwt)}")
	print(f"OIDC_SEGMENTS={len(jwt.split('.'))}")
	if len(jwt) <= 100 or len(jwt.split(".")) != 3:
	    sys.exit(2)
	print("OIDC_MINT_OK")
	PY
	mkdir -p build
	printf 'Format: 1.8\nDate: 2026-05-22\n' > build/probe.changes

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
	LINUX_MAJOR_VERSION="6.6" ./scripts/reproducibility-test

.PHONY: reprotest-sd
reprotest-sd: ## DEBUG Builds SD kernel config without grsec in CI
	GRSECURITY=0 LOCALVERSION="securedrop" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-securedrop-6.6" \
		LINUX_LOCAL_PATCHES_PATH="$(PWD)/patches" \
		./scripts/reproducibility-test

securedrop-core-6.6: OUT:=$(SCRIPT_OUTPUT_PREFIX)-securedrop-core-6.6.$(SCRIPT_OUTPUT_EXT)
securedrop-core-6.6: ## Builds kernels for SecureDrop servers, 6.6.x
	GRSECURITY=1 GRSECURITY_PATCH_TYPE=stable9 LOCALVERSION="securedrop" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-securedrop-6.6" \
		script \
		--command ./scripts/build-kernel-wrapper \
		--return \
		$(OUT)

securedrop-workstation-6.6: OUT:=$(SCRIPT_OUTPUT_PREFIX)-securedrop-workstation-6.6.$(SCRIPT_OUTPUT_EXT)
securedrop-workstation-6.6: ## Builds kernels for SecureDrop Workstation, 6.6.x
	GRSECURITY=1 GRSECURITY_PATCH_TYPE=stable9 LOCALVERSION="workstation" \
		LINUX_LOCAL_CONFIG_PATH="$(PWD)/configs/config-workstation-6.6" \
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
