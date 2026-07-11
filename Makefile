SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ENV ?= dev
REGION ?= ap-south-1
TF_DIR := terraform/envs/$(ENV)
TF_ROOTS := terraform/bootstrap terraform/envs/dev terraform/envs/staging terraform/envs/prod

# State bucket is created by terraform/bootstrap; name is deterministic per account.
ACCOUNT_ID = $(shell aws sts get-caller-identity --query Account --output text)
STATE_BUCKET = eksp-tfstate-$(ACCOUNT_ID)

##@ General

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

.PHONY: tools
tools: ## Verify required tools are installed
	@for t in terraform tflint kubeconform kustomize helm kubectl aws go; do \
		command -v $$t >/dev/null || { echo "MISSING: $$t"; exit 1; }; done; echo "all tools present"

##@ Quality (safe — no cloud access)

.PHONY: fmt
fmt: ## Format all Terraform
	terraform fmt -recursive terraform/

.PHONY: fmt-check
fmt-check: ## Check Terraform formatting
	terraform fmt -check -recursive terraform/

.PHONY: lint
lint: ## tflint across all Terraform
	tflint --recursive

.PHONY: validate
validate: ## terraform validate every root (offline)
	@for d in $(TF_ROOTS); do \
		echo "== $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$d validate || exit 1; \
	done

.PHONY: tf-test
tf-test: ## Run terraform native tests (mocked, offline) for every module with tests
	@for d in terraform/modules/*/tests; do \
		m=$$(dirname $$d); echo "== $$m"; \
		terraform -chdir=$$m init -backend=false -input=false >/dev/null; \
		terraform -chdir=$$m test || exit 1; \
	done

.PHONY: helm-lint
helm-lint: ## Lint local charts
	helm lint terraform/charts/karpenter-resources

.PHONY: kubeconform
kubeconform: ## Validate every kustomize overlay against schemas
	./scripts/validate-manifests.sh

.PHONY: app-test
app-test: ## Unit-test both applications
	cd apps/sample-api && go vet ./... && go test ./...
	cd apps/costwatch/backend && go vet ./... && go test ./...

.PHONY: frontend-build
frontend-build: ## Typecheck + build costwatch UI (emits into backend/web/dist)
	cd apps/costwatch/frontend && npm ci && npm run build

.PHONY: frontend-test
frontend-test: ## Unit-test the costwatch UI (vitest)
	cd apps/costwatch/frontend && npm run test

.PHONY: env-parity
env-parity: ## Shared env files must not silently diverge (ADR-0002 guard)
	./scripts/check-env-parity.sh

.PHONY: check
check: fmt-check lint validate tf-test helm-lint kubeconform app-test env-parity ## Everything CI runs, locally

##@ Deploy (requires AWS credentials — intentionally explicit)

.PHONY: bootstrap
bootstrap: ## One-time: state bucket, GitHub OIDC roles, ECR (local state)
	terraform -chdir=terraform/bootstrap init
	terraform -chdir=terraform/bootstrap apply

.PHONY: init
init: ## Init $(ENV) against the S3 backend
	terraform -chdir=$(TF_DIR) init \
		-backend-config="bucket=$(STATE_BUCKET)" \
		-backend-config="key=envs/$(ENV)/terraform.tfstate" \
		-backend-config="region=$(REGION)" \
		-backend-config="use_lockfile=true"

.PHONY: plan
plan: ## Plan $(ENV)
	terraform -chdir=$(TF_DIR) plan

.PHONY: apply
apply: ## Apply $(ENV)
	terraform -chdir=$(TF_DIR) apply

.PHONY: destroy
destroy: ## Destroy $(ENV) (asks twice — costs stop, data goes)
	@read -p "Really destroy $(ENV)? Type the env name to confirm: " c && [ "$$c" = "$(ENV)" ]
	terraform -chdir=$(TF_DIR) destroy

.PHONY: kubeconfig
kubeconfig: ## Point kubectl at the $(ENV) cluster
	aws eks update-kubeconfig --name eksp-$(ENV) --region $(REGION)

##@ Access (port-forwards; nothing is exposed publicly by default)

.PHONY: argocd-ui
argocd-ui: ## ArgoCD at http://localhost:8080
	@echo "user: admin  password: make argocd-password"
	kubectl -n argocd port-forward svc/argocd-server 8080:80

.PHONY: argocd-password
argocd-password: ## Print the ArgoCD admin password
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

.PHONY: grafana-ui
grafana-ui: ## Grafana at http://localhost:3000
	kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80

.PHONY: costwatch-ui
costwatch-ui: ## costwatch at http://localhost:8090
	kubectl -n costwatch port-forward svc/costwatch 8090:80

.PHONY: costwatch-demo
costwatch-demo: ## Run costwatch locally with synthetic data (no AWS needed)
	cd apps/costwatch/backend && go run ./cmd/costwatch -demo

##@ Load

.PHONY: k6-smoke
k6-smoke: ## Sanity load test (BASE_URL=http://...)
	k6 run load/k6/smoke.js

.PHONY: k6-ramp
k6-ramp: ## Ramp to TARGET_RPS (default 17000) — see docs/SCALING.md first
	k6 run load/k6/ramp.js
