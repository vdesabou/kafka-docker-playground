#!/bin/bash
set -e

#############################################
# Automated Setup Script
# Installs dependencies and configures environment
# No manual steps required!
#############################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${SCRIPT_DIR}/../../scripts/utils.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Terraform Cloud Connector Tool - Automated Setup     ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

function print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

function print_success() {
    echo -e "${GREEN}✔ $1${NC}"
}

function print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

function print_error() {
    echo -e "${RED}✖ $1${NC}"
}

function check_os() {
    print_step "Detecting operating system..."

    OS_TYPE=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        print_success "macOS detected"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS_TYPE="linux"
        print_success "Linux detected"
    else
        print_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
}

function install_terraform() {
    print_step "Checking Terraform installation..."

    if command -v terraform &> /dev/null; then
        TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
        print_success "Terraform already installed (version $TERRAFORM_VERSION)"
        return 0
    fi

    print_warning "Terraform not found. Installing..."

    if [[ "$OS_TYPE" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew tap hashicorp/tap
            brew install hashicorp/tap/terraform
            print_success "Terraform installed via Homebrew"
        else
            print_error "Homebrew not found. Please install Homebrew first: https://brew.sh"
            exit 1
        fi
    elif [[ "$OS_TYPE" == "linux" ]]; then
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install terraform
        print_success "Terraform installed via apt"
    fi
}

function install_jq() {
    print_step "Checking jq installation..."

    if command -v jq &> /dev/null; then
        print_success "jq already installed"
        return 0
    fi

    print_warning "jq not found. Installing..."

    if [[ "$OS_TYPE" == "macos" ]]; then
        brew install jq
    elif [[ "$OS_TYPE" == "linux" ]]; then
        sudo apt-get install -y jq
    fi

    print_success "jq installed"
}

function install_confluent_cli() {
    print_step "Checking Confluent CLI installation..."

    if command -v confluent &> /dev/null; then
        print_success "Confluent CLI already installed"
        return 0
    fi

    print_warning "Confluent CLI not found. Installing..."

    if [[ "$OS_TYPE" == "macos" ]]; then
        brew install confluentinc/tap/cli
    elif [[ "$OS_TYPE" == "linux" ]]; then
        curl -sL --http1.1 https://cnfl.io/cli | sh -s -- latest
    fi

    print_success "Confluent CLI installed"
}

function check_credentials() {
    print_step "Checking Confluent Cloud credentials..."

    if [[ -z "$CONFLUENT_CLOUD_API_KEY" ]] || [[ -z "$CONFLUENT_CLOUD_API_SECRET" ]]; then
        print_warning "Credentials not found in environment variables"

        # Check if credentials file exists
        if [[ -f "$HOME/.confluent/config.json" ]]; then
            print_success "Found credentials in ~/.confluent/config.json"

            # Extract credentials if possible
            if command -v jq &> /dev/null; then
                API_KEY=$(jq -r '.api_key // empty' "$HOME/.confluent/config.json")
                if [[ -n "$API_KEY" ]]; then
                    export CONFLUENT_CLOUD_API_KEY="$API_KEY"
                    export CONFLUENT_CLOUD_API_SECRET=$(jq -r '.api_secret // empty' "$HOME/.confluent/config.json")
                    print_success "Loaded credentials from config file"
                    return 0
                fi
            fi
        fi

        # Prompt for credentials
        echo ""
        echo -e "${YELLOW}Please enter your Confluent Cloud credentials:${NC}"
        echo "You can find these at: https://confluent.cloud/settings/api-keys"
        echo ""

        read -p "API Key: " API_KEY
        read -s -p "API Secret: " API_SECRET
        echo ""

        if [[ -z "$API_KEY" ]] || [[ -z "$API_SECRET" ]]; then
            print_error "Credentials cannot be empty"
            exit 1
        fi

        export CONFLUENT_CLOUD_API_KEY="$API_KEY"
        export CONFLUENT_CLOUD_API_SECRET="$API_SECRET"

        # Save to .env file
        cat > "$SCRIPT_DIR/.env" << EOF
export CONFLUENT_CLOUD_API_KEY="$API_KEY"
export CONFLUENT_CLOUD_API_SECRET="$API_SECRET"
EOF

        print_success "Credentials saved to .env file"
    else
        print_success "Credentials found in environment"
    fi

    # Validate credentials
    print_step "Validating credentials..."
    if confluent api-key list &> /dev/null; then
        print_success "Credentials are valid!"
    else
        print_warning "Could not validate credentials (Confluent CLI may need authentication)"
    fi
}

function setup_aws_credentials() {
    print_step "Checking AWS credentials (optional)..."

    if [[ -n "$AWS_ACCESS_KEY_ID" ]] && [[ -n "$AWS_SECRET_ACCESS_KEY" ]]; then
        print_success "AWS credentials found"
        return 0
    fi

    if [[ -f "$HOME/.aws/credentials" ]]; then
        print_success "AWS credentials file exists"
        return 0
    fi

    print_warning "AWS credentials not found (needed for S3, Kinesis connectors)"
    echo "Skip this by pressing Enter, or provide credentials:"

    read -p "AWS Access Key ID (optional): " AWS_KEY
    if [[ -n "$AWS_KEY" ]]; then
        read -s -p "AWS Secret Access Key: " AWS_SECRET
        echo ""
        read -p "AWS Region (default: us-east-1): " AWS_REGION
        AWS_REGION=${AWS_REGION:-us-east-1}

        # Append to .env file
        cat >> "$SCRIPT_DIR/.env" << EOF
export AWS_ACCESS_KEY_ID="$AWS_KEY"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET"
export AWS_REGION="$AWS_REGION"
EOF

        print_success "AWS credentials saved"
    fi
}

function initialize_terraform() {
    print_step "Initializing Terraform..."

    cd "$SCRIPT_DIR"

    if [[ -d ".terraform" ]]; then
        print_warning ".terraform directory exists, re-initializing..."
    fi

    terraform init -upgrade
    print_success "Terraform initialized"
}

function create_example_configs() {
    print_step "Creating example configuration files..."

    # Create examples directory if it doesn't exist
    mkdir -p "$SCRIPT_DIR/examples"

    # Generate datagen example if not exists
    if [[ ! -f "$SCRIPT_DIR/examples/datagen.json" ]]; then
        cat > "$SCRIPT_DIR/examples/datagen.json" << 'EOF'
{
  "connector.class": "DatagenSource",
  "kafka.auth.mode": "SERVICE_ACCOUNT",
  "kafka.topic": "pageviews",
  "quickstart": "PAGEVIEWS",
  "output.data.format": "JSON",
  "tasks.max": "1"
}
EOF
        print_success "Created examples/datagen.json"
    fi

    # Create README in examples
    if [[ ! -f "$SCRIPT_DIR/examples/README.md" ]]; then
        cat > "$SCRIPT_DIR/examples/README.md" << 'EOF'
# Connector Examples

This directory contains example connector configurations.

## Quick Start

Run any example:
```bash
make datagen  # Datagen source
make s3-sink  # S3 sink (requires AWS credentials)
```

## Available Examples

- `datagen.json` - Generate test data
- `s3-sink.json` - Stream to AWS S3
- More examples can be generated with `./generate-examples.sh`
EOF
        print_success "Created examples/README.md"
    fi
}

function run_validation() {
    print_step "Running validation checks..."

    cd "$SCRIPT_DIR"

    if [[ -f "validate-setup.sh" ]]; then
        ./validate-setup.sh
        print_success "Validation completed"
    else
        print_warning "Validation script not found, skipping"
    fi
}

function print_next_steps() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗"
    echo "║  Setup Complete! 🎉                                    ║"
    echo "╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo ""
    echo "1. Load environment variables:"
    echo -e "   ${YELLOW}source .env${NC}"
    echo ""
    echo "2. Run your first connector:"
    echo -e "   ${YELLOW}make datagen${NC}"
    echo ""
    echo "3. Check status:"
    echo -e "   ${YELLOW}make status${NC}"
    echo ""
    echo "4. View outputs:"
    echo -e "   ${YELLOW}make outputs${NC}"
    echo ""
    echo "5. Clean up when done:"
    echo -e "   ${YELLOW}make destroy${NC}"
    echo ""
    echo -e "${BLUE}Alternative: Use the interactive wizard${NC}"
    echo -e "   ${YELLOW}./wizard.sh${NC}"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "   - Quick Start: QUICKSTART.md"
    echo "   - Full Guide: README.md"
    echo "   - Examples: examples/"
    echo ""
}

# Main execution
main() {
    print_header

    check_os
    install_terraform
    install_jq
    install_confluent_cli
    check_credentials
    setup_aws_credentials
    initialize_terraform
    create_example_configs
    run_validation

    print_next_steps
}

main
