#!/bin/bash
set -e

#############################################
# Bootstrap Script
# Complete end-to-end automation
# From zero to running connector in one command!
#############################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

function print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║   🚀 Terraform Cloud Connector - Bootstrap                ║
║                                                            ║
║   Zero to Hero in One Command!                            ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

function show_menu() {
    echo ""
    echo -e "${BLUE}Choose your adventure:${NC}"
    echo ""
    echo "1) 🎯 Quick Start - Datagen (recommended for first time)"
    echo "2) 🔧 Interactive Wizard - Guided setup"
    echo "3) ⚡ One-Command Launch - Specific scenario"
    echo "4) 📚 Setup Only - Install dependencies and configure"
    echo "5) ❓ Help - Show documentation"
    echo ""
}

function quick_start() {
    echo -e "${BLUE}Starting Quick Start...${NC}"

    # Run setup if needed
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        "$SCRIPT_DIR/setup.sh"
    fi

    # Run datagen
    cd "$SCRIPT_DIR"
    source .env

    echo ""
    echo -e "${GREEN}Launching your first Confluent Cloud cluster with Datagen...${NC}"

    make datagen

    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}Success! Your cluster is ready! 🎉${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "What just happened:"
    echo "  ✔ Created a Kafka cluster in Confluent Cloud"
    echo "  ✔ Deployed a Datagen connector"
    echo "  ✔ Started generating test data (pageviews)"
    echo ""
    echo "Next steps:"
    echo "  1. Check status: make status"
    echo "  2. View outputs: make outputs"
    echo "  3. Clean up: make destroy"
    echo ""
}

function run_wizard() {
    echo -e "${BLUE}Starting Interactive Wizard...${NC}"
    "$SCRIPT_DIR/wizard.sh"
}

function one_command() {
    echo ""
    echo -e "${BLUE}One-Command Launch Options:${NC}"
    echo ""
    echo "1) Datagen - Test data generator"
    echo "2) S3 Pipeline - Complete Datagen → S3"
    echo "3) Demo - Full multi-connector demo"
    echo ""

    read -p "Choice: " choice

    case $choice in
        1) "$SCRIPT_DIR/quick-launch.sh" datagen;;
        2) "$SCRIPT_DIR/quick-launch.sh" pipeline;;
        3) "$SCRIPT_DIR/quick-launch.sh" demo;;
        *) echo "Invalid choice"; exit 1;;
    esac
}

function setup_only() {
    echo -e "${BLUE}Running setup...${NC}"
    "$SCRIPT_DIR/setup.sh"
}

function show_help() {
    cat << EOF

${BLUE}═════════════════════════════════════════════════════════${NC}
${GREEN}Terraform Cloud Connector Tool - Help${NC}
${BLUE}═════════════════════════════════════════════════════════${NC}

${CYAN}📚 Documentation Files:${NC}
  - QUICKSTART.md    Quick 5-minute guide
  - README.md        Complete documentation
  - PLAYGROUND_RUN.md   Playground integration guide
  - OVERVIEW.md      Architecture and concepts

${CYAN}🔧 Available Scripts:${NC}
  - bootstrap.sh     This script (complete automation)
  - setup.sh         Install dependencies and configure
  - wizard.sh        Interactive guided setup
  - quick-launch.sh  One-command scenario launchers
  - terraform-cloud-connector.sh  Main CLI tool

${CYAN}📦 Make Commands:${NC}
  - make datagen     Quick Datagen test
  - make s3-sink     S3 sink connector
  - make plan        Preview changes
  - make apply       Deploy infrastructure
  - make destroy     Clean up resources
  - make status      Check connector status
  - make outputs     View cluster details

${CYAN}🎯 Common Workflows:${NC}

  First Time User:
    ./bootstrap.sh
    → Choose option 1 (Quick Start)

  Want Guidance:
    ./wizard.sh

  Know What You Want:
    ./quick-launch.sh datagen
    ./quick-launch.sh pipeline

  Full Control:
    ./terraform-cloud-connector.sh --help

${CYAN}🆘 Getting Help:${NC}
  - Documentation: cat README.md
  - Examples: ls examples/
  - Validation: ./validate-setup.sh
  - GitHub Issues: https://github.com/vdesabou/kafka-docker-playground/issues

${BLUE}═════════════════════════════════════════════════════════${NC}

EOF
}

# Main menu
main() {
    print_banner

    # Check if running for first time
    if [[ ! -f "$SCRIPT_DIR/.env" ]] && [[ ! -f "$SCRIPT_DIR/.terraform/terraform.tfstate" ]]; then
        echo -e "${GREEN}Welcome! This looks like your first time.${NC}"
        echo ""
        echo "I recommend starting with the Quick Start (Option 1)"
        echo "It will set everything up and deploy your first connector."
        echo ""
        sleep 2
    fi

    show_menu

    read -p "Enter your choice (1-5): " choice

    case $choice in
        1) quick_start;;
        2) run_wizard;;
        3) one_command;;
        4) setup_only;;
        5) show_help;;
        *) echo "Invalid choice. Run ./bootstrap.sh --help"; exit 1;;
    esac
}

# Handle command line args
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
elif [[ "$1" == "--quick" ]]; then
    quick_start
    exit 0
fi

main
