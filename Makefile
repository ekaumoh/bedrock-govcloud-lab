SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
PY := .venv/bin/python

.PHONY: help venv preflight smoke first-call vpce-up vpce-down iam logging guardrail \
        kb-upload kb-sync kb-canary rag tools tf-init tf-plan tf-apply tf-destroy \
        cleanup verify lint

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n",$$1,$$2}'

$(PY): requirements.txt
	python3 -m venv .venv && $(PY) -m pip install -q -r requirements.txt && touch $(PY)

venv: $(PY) ## Create .venv and install boto3

# ---- Lab modules (run in order) -----------------------------------------------
preflight: ## 0  Partition, Region, identity, model
	scripts/00-preflight.sh

smoke: ## 1  Prove the model is callable (pass extra IDs: make smoke MODELS="a b")
	scripts/01-smoke-test.sh $(MODELS)

first-call: $(PY) ## 1b Converse + streaming from Python
	cd src && ../$(PY) first_call.py

vpce-up: ## 2  Interface VPC endpoint (bills hourly)
	scripts/02-vpce-up.sh

vpce-down: ## 2  Delete the VPC endpoint
	scripts/03-vpce-down.sh

iam: ## 3  Least-privilege role: one model allowed, another denied
	scripts/04-iam-least-privilege.sh

logging: ## 4  Invocation logging to an encrypted, private S3 bucket
	scripts/05-logging-up.sh

guardrail: ## 5  Create, version, and test a guardrail four ways
	scripts/06-guardrail-up.sh

kb-upload: ## 6  Upload sample docs (then create the KB in the console)
	scripts/07-kb.sh upload

kb-sync: ## 6  Sync every data source: make kb-sync KB_ID=...
	scripts/07-kb.sh sync $(KB_ID)

kb-canary: ## 6  Known question per document returns the right file
	scripts/07-kb.sh canary $(KB_ID)

rag: $(PY) ## 6  Retrieve-then-generate with citations: make rag Q="..."
	cd src && ../$(PY) rag.py "$(Q)"

tools: $(PY) ## 7  Tool-use loop with allow-list and turn cap
	cd src && ../$(PY) tool_use.py

# ---- Terraform ----------------------------------------------------------------
tf-init: ## 8  terraform init
	terraform -chdir=terraform init

tf-plan: ## 8  terraform plan
	terraform -chdir=terraform plan

tf-apply: ## 8  terraform apply
	terraform -chdir=terraform apply

tf-destroy: ## 8  terraform destroy
	terraform -chdir=terraform destroy

# ---- Teardown -----------------------------------------------------------------
cleanup: ## 9  Delete every lab resource (asks first)
	scripts/90-cleanup.sh

verify: ## 9  Confirm zero lab resources remain
	scripts/91-verify-clean.sh

lint: ## Run the same checks as CI
	shellcheck -x -S warning scripts/*.sh scripts/lib/*.sh
	ruff check src && ruff format --check src
	terraform -chdir=terraform fmt -check -recursive
