.PHONY: help init plan apply destroy clean validate format check-env

# Default target
help:
	@echo "🎯 Terraform Cloud Connector Tool - Available Commands"
	@echo "=================================================="
	@echo ""
	@echo "Setup:"
	@echo "  make init              Initialize Terraform"
	@echo "  make check-env         Verify environment variables"
	@echo ""
	@echo "Development:"
	@echo "  make plan              Preview infrastructure changes"
	@echo "  make apply             Apply infrastructure changes"
	@echo "  make destroy           Destroy all resources"
	@echo ""
	@echo "Maintenance:"
	@echo "  make validate          Validate Terraform configuration"
	@echo "  make format            Format Terraform files"
	@echo "  make clean             Clean Terraform artifacts"
	@echo ""
	@echo "🚀 Zero-Config Automation (NEW!):"
	@echo "  make bootstrap            Complete automated setup (recommended for first time)"
	@echo "  make wizard               Interactive wizard for guided setup"
	@echo "  make quick-datagen        Quick launch: Datagen only"
	@echo "  make quick-pipeline       Quick launch: Complete pipeline"
	@echo "  make setup                Setup only (install dependencies)"
	@echo ""
	@echo "Quick Start Examples:"
	@echo "  make datagen              Create cluster with Datagen connector"
	@echo "  make s3-sink              Create cluster with S3 sink connector"
	@echo "  make playground-datagen   Run Datagen example (playground style)"
	@echo "  make playground-s3        Run S3 example (playground style)"
	@echo ""

# Check environment variables
check-env:
	@echo "🔍 Checking environment variables..."
	@test -n "$(CONFLUENT_CLOUD_API_KEY)" || (echo "❌ CONFLUENT_CLOUD_API_KEY not set" && exit 1)
	@test -n "$(CONFLUENT_CLOUD_API_SECRET)" || (echo "❌ CONFLUENT_CLOUD_API_SECRET not set" && exit 1)
	@echo "✅ Required environment variables are set"

# Initialize Terraform
init: check-env
	@echo "🔧 Initializing Terraform..."
	@terraform init

# Validate configuration
validate: init
	@echo "✅ Validating Terraform configuration..."
	@terraform validate

# Format Terraform files
format:
	@echo "📝 Formatting Terraform files..."
	@terraform fmt -recursive

# Plan infrastructure
plan: check-env init
	@echo "📋 Planning infrastructure changes..."
	@./terraform-cloud-connector.sh --plan

# Apply infrastructure
apply: check-env init
	@echo "🚀 Applying infrastructure changes..."
	@./terraform-cloud-connector.sh --apply

# Destroy infrastructure
destroy:
	@echo "🗑️  Destroying infrastructure..."
	@./terraform-cloud-connector.sh --destroy

# Clean Terraform artifacts
clean:
	@echo "🧹 Cleaning Terraform artifacts..."
	@rm -rf .terraform .terraform.lock.hcl terraform.tfstate* terraform.tfvars .ccloud_env
	@echo "✅ Cleanup complete"

# Quick start: Datagen connector
datagen: check-env init
	@echo "🎲 Creating cluster with Datagen connector..."
	@./terraform-cloud-connector.sh --apply \
		--connector-type DATAGEN \
		--connector-config examples/datagen.json

# Run Datagen example with playground
playground-datagen: check-env
	@echo "🎲 Running Datagen example with playground..."
	@./terraform-datagen-example.sh

# Run S3 Sink example with playground
playground-s3: check-env
	@test -n "$(AWS_ACCESS_KEY_ID)" || (echo "❌ AWS_ACCESS_KEY_ID not set" && exit 1)
	@test -n "$(AWS_SECRET_ACCESS_KEY)" || (echo "❌ AWS_SECRET_ACCESS_KEY not set" && exit 1)
	@echo "☁️  Running S3 Sink example with playground..."
	@./terraform-s3-sink-example.sh

# Quick start: S3 Sink connector
s3-sink: check-env
	@test -n "$(AWS_ACCESS_KEY_ID)" || (echo "❌ AWS_ACCESS_KEY_ID not set" && exit 1)
	@test -n "$(AWS_SECRET_ACCESS_KEY)" || (echo "❌ AWS_SECRET_ACCESS_KEY not set" && exit 1)
	@echo "☁️  Creating cluster with S3 Sink connector..."
	@./terraform-cloud-connector.sh --apply \
		--connector-type S3_SINK \
		--connector-config examples/s3-sink.json

# Show outputs
outputs:
	@echo "📊 Terraform outputs:"
	@terraform output -json | jq '.'

# Show connector status
status:
	@echo "🔌 Connector status:"
	@terraform output -json | jq -r '.connector_status.value // empty'

# Install dependencies (Terraform)
install-deps:
	@echo "📦 Installing dependencies..."
	@which terraform > /dev/null || (echo "Installing Terraform..." && \
		curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add - && \
		sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" && \
		sudo apt-get update && sudo apt-get install terraform)
	@echo "✅ Dependencies installed"

# Zero-Config Automation Scripts
bootstrap:
	@echo "🚀 Running complete automated setup..."
	@./bootstrap.sh

wizard:
	@echo "🔧 Starting interactive wizard..."
	@./wizard.sh

quick-datagen:
	@echo "⚡ Quick launching Datagen..."
	@./quick-launch.sh datagen

quick-pipeline:
	@echo "⚡ Quick launching complete pipeline..."
	@./quick-launch.sh pipeline

quick-demo:
	@echo "⚡ Quick launching full demo..."
	@./quick-launch.sh demo

setup:
	@echo "🛠️  Running setup (dependencies and configuration)..."
	@./setup.sh
