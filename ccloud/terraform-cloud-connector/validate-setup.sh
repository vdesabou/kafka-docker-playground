#!/bin/bash

#############################################
# Setup Validation Script
#
# Validates that all prerequisites are met
# before using the Terraform Cloud Connector Tool
#############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

function check_pass() {
    echo -e "${GREEN}✅ $1${NC}"
}

function check_fail() {
    echo -e "${RED}❌ $1${NC}"
}

function check_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

function check_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

ERRORS=0
WARNINGS=0

print_header "Terraform Cloud Connector - Setup Validation"

# Check 1: Terraform Installation
print_header "Checking Terraform Installation"
if command -v terraform &> /dev/null; then
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    check_pass "Terraform is installed (version: $TERRAFORM_VERSION)"

    # Check version requirement (>= 1.0.0)
    MAJOR_VERSION=$(echo $TERRAFORM_VERSION | cut -d. -f1)
    if [ "$MAJOR_VERSION" -ge 1 ]; then
        check_pass "Terraform version meets requirement (>= 1.0.0)"
    else
        check_fail "Terraform version is too old. Required: >= 1.0.0, Found: $TERRAFORM_VERSION"
        ((ERRORS++))
    fi
else
    check_fail "Terraform is not installed"
    check_info "Install from: https://www.terraform.io/downloads"
    ((ERRORS++))
fi

# Check 2: Confluent Cloud API Credentials
print_header "Checking Confluent Cloud Credentials"
if [ -n "$CONFLUENT_CLOUD_API_KEY" ]; then
    check_pass "CONFLUENT_CLOUD_API_KEY is set"
    KEY_LENGTH=${#CONFLUENT_CLOUD_API_KEY}
    if [ $KEY_LENGTH -gt 10 ]; then
        check_pass "API key format looks valid (length: $KEY_LENGTH)"
    else
        check_warn "API key seems too short (length: $KEY_LENGTH)"
        ((WARNINGS++))
    fi
else
    check_fail "CONFLUENT_CLOUD_API_KEY is not set"
    check_info "Export it: export CONFLUENT_CLOUD_API_KEY='your-key'"
    ((ERRORS++))
fi

if [ -n "$CONFLUENT_CLOUD_API_SECRET" ]; then
    check_pass "CONFLUENT_CLOUD_API_SECRET is set"
    SECRET_LENGTH=${#CONFLUENT_CLOUD_API_SECRET}
    if [ $SECRET_LENGTH -gt 20 ]; then
        check_pass "API secret format looks valid (length: $SECRET_LENGTH)"
    else
        check_warn "API secret seems too short (length: $SECRET_LENGTH)"
        ((WARNINGS++))
    fi
else
    check_fail "CONFLUENT_CLOUD_API_SECRET is not set"
    check_info "Export it: export CONFLUENT_CLOUD_API_SECRET='your-secret'"
    ((ERRORS++))
fi

# Check 3: Optional - AWS Credentials (for AWS connectors)
print_header "Checking AWS Credentials (Optional)"
if [ -n "$AWS_ACCESS_KEY_ID" ]; then
    check_pass "AWS_ACCESS_KEY_ID is set"
else
    check_info "AWS_ACCESS_KEY_ID is not set (required for AWS connectors)"
fi

if [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    check_pass "AWS_SECRET_ACCESS_KEY is set"
else
    check_info "AWS_SECRET_ACCESS_KEY is not set (required for AWS connectors)"
fi

if [ -n "$AWS_REGION" ]; then
    check_pass "AWS_REGION is set to: $AWS_REGION"
else
    check_info "AWS_REGION is not set (will default to us-east-1)"
fi

# Check 4: Required Tools
print_header "Checking Additional Tools"
if command -v jq &> /dev/null; then
    check_pass "jq is installed"
else
    check_warn "jq is not installed (recommended for JSON processing)"
    check_info "Install: brew install jq (macOS) or apt-get install jq (Linux)"
    ((WARNINGS++))
fi

if command -v aws &> /dev/null; then
    check_pass "AWS CLI is installed"
else
    check_info "AWS CLI is not installed (required for AWS S3 connectors)"
fi

if command -v git &> /dev/null; then
    check_pass "git is installed"
else
    check_warn "git is not installed"
    ((WARNINGS++))
fi

# Check 5: Directory Structure
print_header "Checking Directory Structure"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ -f "$DIR/main.tf" ]; then
    check_pass "main.tf found"
else
    check_fail "main.tf not found"
    ((ERRORS++))
fi

if [ -f "$DIR/variables.tf" ]; then
    check_pass "variables.tf found"
else
    check_fail "variables.tf not found"
    ((ERRORS++))
fi

if [ -f "$DIR/outputs.tf" ]; then
    check_pass "outputs.tf found"
else
    check_fail "outputs.tf not found"
    ((ERRORS++))
fi

if [ -f "$DIR/connectors.tf" ]; then
    check_pass "connectors.tf found"
else
    check_fail "connectors.tf not found"
    ((ERRORS++))
fi

if [ -f "$DIR/terraform-cloud-connector.sh" ]; then
    check_pass "terraform-cloud-connector.sh found"
    if [ -x "$DIR/terraform-cloud-connector.sh" ]; then
        check_pass "terraform-cloud-connector.sh is executable"
    else
        check_warn "terraform-cloud-connector.sh is not executable"
        check_info "Fix: chmod +x terraform-cloud-connector.sh"
        ((WARNINGS++))
    fi
else
    check_fail "terraform-cloud-connector.sh not found"
    ((ERRORS++))
fi

if [ -d "$DIR/examples" ]; then
    check_pass "examples/ directory found"
    EXAMPLE_COUNT=$(ls -1 $DIR/examples/*.json 2>/dev/null | wc -l)
    check_pass "Found $EXAMPLE_COUNT example configurations"
else
    check_warn "examples/ directory not found"
    ((WARNINGS++))
fi

# Check 6: Terraform Configuration Validation
if [ -f "$DIR/main.tf" ] && command -v terraform &> /dev/null; then
    print_header "Validating Terraform Configuration"
    cd "$DIR"

    if [ -d ".terraform" ]; then
        check_info "Terraform already initialized"
    else
        check_info "Running terraform init..."
        if terraform init > /dev/null 2>&1; then
            check_pass "Terraform initialized successfully"
        else
            check_fail "Terraform initialization failed"
            ((ERRORS++))
        fi
    fi

    if terraform validate > /dev/null 2>&1; then
        check_pass "Terraform configuration is valid"
    else
        check_fail "Terraform configuration validation failed"
        check_info "Run: terraform validate"
        ((ERRORS++))
    fi
fi

# Summary
print_header "Validation Summary"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    check_pass "All checks passed! ✨"
    echo ""
    check_info "You're ready to use the Terraform Cloud Connector Tool!"
    echo ""
    echo "Quick start:"
    echo "  ./terraform-cloud-connector.sh --apply --connector-type DATAGEN --connector-config examples/datagen.json"
    echo ""
    echo "Or use Make:"
    echo "  make datagen"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    check_pass "All required checks passed"
    check_warn "Found $WARNINGS warning(s) - tool should work but some features may be limited"
    exit 0
else
    check_fail "Found $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    echo -e "${RED}Please fix the errors above before proceeding.${NC}"
    exit 1
fi
