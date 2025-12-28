# Chert Blockchain - Development and Deployment Makefile
# Provides common tasks for building, testing, and deploying Silica nodes

.PHONY: help build test docker-build docker-push deploy-local deploy-testnet deploy-prod clean lint security-scan

# Default target
help: ## Display this help message
	@echo "Chert Blockchain - Available Make Targets:"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Environment Variables:"
	@echo "  IMAGE_TAG       Container image tag (default: latest)"
	@echo "  REGISTRY        Container registry (default: ghcr.io/dedme/chert)"
	@echo "  ENVIRONMENT     Deployment environment (dev|testnet|mainnet)"

# Configuration
REGISTRY ?= ghcr.io/dedme/chert
IMAGE_TAG ?= latest
ENVIRONMENT ?= dev
PROJECT_NAME = chert
BINARY_NAME = silica

# Build configuration
CARGO_FLAGS = --release
DOCKER_BUILDKIT = 1
RUST_LOG ?= info

###################
# Development     #
###################

build: ## Build Silica binary
	@echo "Building Silica blockchain node..."
	cargo build $(CARGO_FLAGS) --package silica
	@echo "Build complete: target/release/$(BINARY_NAME)"

test: ## Run all tests
	@echo "Running test suite..."
	cargo test --workspace --all-features
	@echo "All tests passed!"

test-integration: ## Run integration tests
	@echo "Running integration tests..."
	cargo test --package silica --test integration -- --test-threads=1
	@echo "Integration tests passed!"

lint: ## Run code linting and formatting checks
	@echo "Checking code formatting..."
	cargo fmt --all -- --check
	@echo "Running Clippy lints..."
	cargo clippy --workspace --all-targets --all-features -- -D warnings
	@echo "Linting complete!"

security-scan: ## Run security audit and vulnerability scan
	@echo "Running security audit..."
	cargo audit
	@echo "Security scan complete!"

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	cargo clean
	rm -rf target/
	docker system prune -f
	@echo "Clean complete!"

###################
# Container       #
###################

docker-build: ## Build Docker container
	@echo "Building Docker container: $(REGISTRY)/silica:$(IMAGE_TAG)"
	DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) docker build \\
		-f docker/Dockerfile.silica \\
		-t $(REGISTRY)/silica:$(IMAGE_TAG) \\
		--label "org.opencontainers.image.version=$(IMAGE_TAG)" \\
		--label "org.opencontainers.image.created=$$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \\
		--label "org.opencontainers.image.source=https://github.com/Dedme/chert" \\
		.
	@echo "Container build complete!"

docker-push: docker-build ## Build and push container to registry
	@echo "Pushing container to registry..."
	docker push $(REGISTRY)/silica:$(IMAGE_TAG)
	@echo "Container push complete!"

docker-run: ## Run container locally
	@echo "Running Silica container locally..."
	docker run --rm -it \\
		-p 8545:8545 \\
		-p 30300:30300 \\
		-v $$(pwd)/data:/data \\
		$(REGISTRY)/silica:$(IMAGE_TAG) \\
		dev-node --data-dir /data

docker-scan: docker-build ## Scan container for vulnerabilities
	@echo "Scanning container for vulnerabilities..."
	docker scout cves $(REGISTRY)/silica:$(IMAGE_TAG) || true
	@echo "Container scan complete!"

###################
# Infrastructure  #
###################

terraform-init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	cd infrastructure/terraform && terraform init
	@echo "Terraform initialization complete!"

terraform-plan: ## Plan Terraform deployment
	@echo "Planning Terraform deployment for $(ENVIRONMENT)..."
	cd infrastructure/terraform && terraform plan \\
		-var-file="environments/$(ENVIRONMENT).tfvars" \\
		-out=$(ENVIRONMENT).tfplan
	@echo "Terraform plan complete!"

terraform-apply: ## Apply Terraform deployment
	@echo "Applying Terraform deployment for $(ENVIRONMENT)..."
	cd infrastructure/terraform && terraform apply $(ENVIRONMENT).tfplan
	@echo "Terraform apply complete!"

terraform-destroy: ## Destroy Terraform infrastructure
	@echo "WARNING: This will destroy infrastructure for $(ENVIRONMENT)"
	@echo "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]
	cd infrastructure/terraform && terraform destroy \\
		-var-file="environments/$(ENVIRONMENT).tfvars"

###################
# Deployment      #
###################

deploy-local: build ## Deploy locally for development
	@echo "Starting local development deployment..."
	mkdir -p data/
	./target/release/$(BINARY_NAME) generate-keys --output data/keys/
	./target/release/$(BINARY_NAME) dev-node --data-dir data/ &
	@echo "Local deployment started! API available at http://localhost:8545"

deploy-testnet: docker-push ## Deploy to testnet
	@echo "Deploying to testnet environment..."
	cd infrastructure/ansible && ansible-playbook \\
		-i inventories/testnet.ini \\
		playbooks/deploy.yml \\
		--extra-vars "image_tag=$(IMAGE_TAG)"
	@echo "Testnet deployment complete!"

deploy-k8s: ## Deploy to Kubernetes
	@echo "Deploying to Kubernetes ($(ENVIRONMENT))..."
	kubectl apply -k manifests/overlays/$(ENVIRONMENT)/
	kubectl rollout status statefulset/silica-validator -n chert-$(ENVIRONMENT)
	@echo "Kubernetes deployment complete!"

###################
# Operations      #
###################

logs: ## View application logs
	@echo "Viewing Silica logs..."
	kubectl logs -f statefulset/silica-validator -n chert-$(ENVIRONMENT)

health-check: ## Check node health
	@echo "Checking node health..."
	curl -f http://localhost:8545/health || echo "Health check failed!"

metrics: ## View node metrics
	@echo "Fetching node metrics..."
	curl -s http://localhost:8545/metrics | head -20

backup: ## Create backup of node data
	@echo "Creating backup..."
	tar -czf backup-$$(date +%Y%m%d-%H%M%S).tar.gz data/
	@echo "Backup created!"

###################
# Development     #
###################

dev-setup: ## Set up development environment
	@echo "Setting up development environment..."
	rustup update stable
	rustup component add rustfmt clippy
	cargo install cargo-audit
	@echo "Development setup complete!"

generate-keys: ## Generate new validator keys
	@echo "Generating new validator keys..."
	mkdir -p keys/
	cargo run --package silica -- generate-keys --output keys/
	@echo "Keys generated in keys/ directory"

simulate: ## Run network simulation
	@echo "Running network simulation..."
	./scripts/run-simulation.sh
	@echo "Simulation complete!"

###################
# CI/CD           #
###################

ci-test: lint test security-scan ## Run full CI test suite
	@echo "All CI tests passed!"

ci-build: ci-test docker-build docker-scan ## Full CI build pipeline
	@echo "CI build pipeline complete!"

release: ## Create a new release
	@echo "Creating release $(IMAGE_TAG)..."
	git tag -a v$(IMAGE_TAG) -m "Release v$(IMAGE_TAG)"
	git push origin v$(IMAGE_TAG)
	$(MAKE) docker-push IMAGE_TAG=$(IMAGE_TAG)
	@echo "Release $(IMAGE_TAG) complete!"

###################
# Monitoring      #
###################

monitoring-setup: ## Set up monitoring stack
	@echo "Setting up monitoring..."
	kubectl apply -k monitoring/overlays/$(ENVIRONMENT)/
	@echo "Monitoring setup complete!"

dashboard: ## Open Grafana dashboard
	@echo "Opening monitoring dashboard..."
	kubectl port-forward svc/grafana 3000:3000 -n monitoring &
	open http://localhost:3000

###################
# Utilities       #
###################

check-deps: ## Check system dependencies
	@echo "Checking system dependencies..."
	@command -v cargo >/dev/null 2>&1 || { echo "cargo is required but not installed."; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "docker is required but not installed."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed."; exit 1; }
	@echo "All dependencies are available!"

status: ## Show deployment status
	@echo "Deployment Status for $(ENVIRONMENT):"
	@echo "=====================================:"
	kubectl get pods -n chert-$(ENVIRONMENT) 2>/dev/null || echo "No Kubernetes deployment found"
	docker ps | grep silica || echo "No local containers running"

version: ## Show version information
	@echo "Chert Blockchain Version Information:"
	@echo "====================================="
	@echo "Project: $(PROJECT_NAME)"
	@echo "Binary: $(BINARY_NAME)"
	@echo "Image Tag: $(IMAGE_TAG)"
	@echo "Registry: $(REGISTRY)"
	@echo "Environment: $(ENVIRONMENT)"
	@cargo --version 2>/dev/null || echo "Cargo not available"
	@docker --version 2>/dev/null || echo "Docker not available"