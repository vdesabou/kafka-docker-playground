#!/bin/bash
set -e

#############################################
# Interactive Wizard
# Guides users through connector setup
# Zero manual configuration!
#############################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

function print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║   ████████╗███████╗██████╗ ██████╗  █████╗ ███████╗ ██████╗ ║
║   ╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔═══██╗║
║      ██║   █████╗  ██████╔╝██████╔╝███████║█████╗  ██║   ██║║
║      ██║   ██╔══╝  ██╔══██╗██╔══██╗██╔══██║██╔══╝  ██║   ██║║
║      ██║   ███████╗██║  ██║██║  ██║██║  ██║██║     ╚██████╔╝║
║      ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝      ╚═════╝ ║
║                                                              ║
║         Cloud Connector Wizard - Interactive Setup          ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

function prompt_choice() {
    local prompt="$1"
    local default="$2"
    local response

    echo -e "${YELLOW}${prompt}${NC}"
    read -p "➤ " response
    echo "${response:-$default}"
}

function prompt_yes_no() {
    local prompt="$1"
    local default="$2"

    while true; do
        echo -e "${YELLOW}${prompt} [y/n] (default: ${default})${NC}"
        read -p "➤ " response
        response="${response:-$default}"

        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

function select_connector_type() {
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}What do you want to do?${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    echo "1) Generate test data (Datagen)"
    echo "2) Stream to AWS S3"
    echo "3) Stream to PostgreSQL"
    echo "4) Stream to MongoDB"
    echo "5) Stream to Elasticsearch"
    echo "6) Stream to HTTP endpoint"
    echo "7) Complete pipeline (Datagen → S3)"
    echo "8) Custom connector"
    echo ""

    local choice=$(prompt_choice "Enter your choice (1-8):" "1")

    case $choice in
        1) CONNECTOR_TYPE="DATAGEN"; CONNECTOR_NAME="datagen";;
        2) CONNECTOR_TYPE="S3_SINK"; CONNECTOR_NAME="s3-sink";;
        3) CONNECTOR_TYPE="POSTGRESQL_SINK"; CONNECTOR_NAME="postgresql-sink";;
        4) CONNECTOR_TYPE="MONGODB_SINK"; CONNECTOR_NAME="mongodb-sink";;
        5) CONNECTOR_TYPE="ELASTICSEARCH_SINK"; CONNECTOR_NAME="elasticsearch-sink";;
        6) CONNECTOR_TYPE="HTTP_SINK"; CONNECTOR_NAME="http-sink";;
        7) CONNECTOR_TYPE="PIPELINE"; CONNECTOR_NAME="pipeline";;
        8) CONNECTOR_TYPE="CUSTOM"; CONNECTOR_NAME="custom";;
        *) echo "Invalid choice, using Datagen"; CONNECTOR_TYPE="DATAGEN"; CONNECTOR_NAME="datagen";;
    esac
}

function select_cloud_provider() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}Which cloud provider?${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    echo "1) AWS (us-east-1)"
    echo "2) AWS (us-west-2)"
    echo "3) GCP (us-central1)"
    echo "4) Azure (eastus)"
    echo "5) Custom"
    echo ""

    local choice=$(prompt_choice "Enter your choice (1-5):" "1")

    case $choice in
        1) CLOUD="AWS"; REGION="us-east-1";;
        2) CLOUD="AWS"; REGION="us-west-2";;
        3) CLOUD="GCP"; REGION="us-central1";;
        4) CLOUD="AZURE"; REGION="eastus";;
        5)
            CLOUD=$(prompt_choice "Cloud provider (AWS/GCP/AZURE):" "AWS")
            REGION=$(prompt_choice "Region:" "us-east-1")
            ;;
        *) CLOUD="AWS"; REGION="us-east-1";;
    esac
}

function configure_datagen() {
    echo ""
    echo -e "${BLUE}Configuring Datagen...${NC}"

    TOPIC=$(prompt_choice "Topic name:" "pageviews")

    echo ""
    echo "Quick start templates:"
    echo "1) PAGEVIEWS"
    echo "2) CLICKSTREAM"
    echo "3) ORDERS"
    echo "4) USERS"
    echo ""

    local template_choice=$(prompt_choice "Choose template (1-4):" "1")
    case $template_choice in
        1) QUICKSTART="PAGEVIEWS";;
        2) QUICKSTART="CLICKSTREAM";;
        3) QUICKSTART="ORDERS";;
        4) QUICKSTART="USERS";;
        *) QUICKSTART="PAGEVIEWS";;
    esac

    # Create config
    cat > /tmp/connector-config.json << EOF
{
  "connector.class": "DatagenSource",
  "kafka.auth.mode": "SERVICE_ACCOUNT",
  "kafka.topic": "$TOPIC",
  "quickstart": "$QUICKSTART",
  "output.data.format": "JSON",
  "tasks.max": "1"
}
EOF
}

function configure_s3_sink() {
    echo ""
    echo -e "${BLUE}Configuring S3 Sink...${NC}"

    TOPIC=$(prompt_choice "Source topic name:" "pageviews")
    S3_BUCKET=$(prompt_choice "S3 bucket name:" "my-kafka-bucket")

    # Check AWS credentials
    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
        echo ""
        echo -e "${YELLOW}AWS credentials needed:${NC}"
        AWS_ACCESS_KEY_ID=$(prompt_choice "AWS Access Key ID:" "")
        read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
        echo ""
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    fi

    # Create config
    cat > /tmp/connector-config.json << EOF
{
  "connector.class": "S3_SINK",
  "kafka.auth.mode": "SERVICE_ACCOUNT",
  "input.data.format": "JSON",
  "topics": "$TOPIC",
  "s3.bucket.name": "$S3_BUCKET",
  "s3.region": "${AWS_REGION:-us-east-1}",
  "output.data.format": "JSON",
  "time.interval": "HOURLY",
  "flush.size": "1000",
  "tasks.max": "1"
}
EOF
}

function configure_pipeline() {
    echo ""
    echo -e "${BLUE}Configuring Complete Pipeline (Datagen → S3)...${NC}"

    TOPIC=$(prompt_choice "Topic name:" "pageviews")
    S3_BUCKET=$(prompt_choice "S3 bucket name:" "my-kafka-bucket")

    # Check AWS credentials
    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
        echo ""
        echo -e "${YELLOW}AWS credentials needed:${NC}"
        AWS_ACCESS_KEY_ID=$(prompt_choice "AWS Access Key ID:" "")
        read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
        echo ""
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    fi

    PIPELINE_MODE="true"
}

function review_configuration() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}Configuration Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    echo -e "Connector Type: ${CYAN}$CONNECTOR_TYPE${NC}"
    echo -e "Connector Name: ${CYAN}$CONNECTOR_NAME${NC}"
    echo -e "Cloud Provider: ${CYAN}$CLOUD${NC}"
    echo -e "Region:         ${CYAN}$REGION${NC}"
    echo -e "Cluster Name:   ${CYAN}playground-terraform-${CONNECTOR_NAME}${NC}"
    echo ""

    if [[ "$CONNECTOR_TYPE" == "DATAGEN" ]]; then
        echo -e "Topic:          ${CYAN}$TOPIC${NC}"
        echo -e "Template:       ${CYAN}$QUICKSTART${NC}"
    elif [[ "$CONNECTOR_TYPE" == "S3_SINK" ]]; then
        echo -e "Topic:          ${CYAN}$TOPIC${NC}"
        echo -e "S3 Bucket:      ${CYAN}$S3_BUCKET${NC}"
    elif [[ "$CONNECTOR_TYPE" == "PIPELINE" ]]; then
        echo -e "Topic:          ${CYAN}$TOPIC${NC}"
        echo -e "S3 Bucket:      ${CYAN}$S3_BUCKET${NC}"
        echo -e "Pipeline:       ${CYAN}Datagen → Kafka → S3${NC}"
    fi

    echo ""
}

function execute_deployment() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}Starting Deployment...${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""

    cd "$SCRIPT_DIR"

    if [[ "$CONNECTOR_TYPE" == "PIPELINE" ]]; then
        # Run pipeline example
        if [[ -f "examples/complete-pipeline.sh" ]]; then
            TOPIC="$TOPIC" S3_BUCKET="$S3_BUCKET" ./examples/complete-pipeline.sh
        else
            echo -e "${YELLOW}Pipeline script not found, running step by step...${NC}"
            configure_datagen
            ./terraform-cloud-connector.sh --apply \
                --connector-type DATAGEN \
                --connector-config /tmp/connector-config.json \
                --cluster-name "playground-terraform-${CONNECTOR_NAME}" \
                --cloud "$CLOUD" \
                --region "$REGION"
        fi
    else
        # Run single connector
        ./terraform-cloud-connector.sh --apply \
            --connector-type "$CONNECTOR_TYPE" \
            --connector-config /tmp/connector-config.json \
            --cluster-name "playground-terraform-${CONNECTOR_NAME}" \
            --cloud "$CLOUD" \
            --region "$REGION"
    fi
}

function show_results() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}Deployment Complete! 🎉${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo ""

    # Show outputs
    terraform output

    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo ""
    echo "1. Check connector status:"
    echo -e "   ${YELLOW}make status${NC}"
    echo ""
    echo "2. View cluster details:"
    echo -e "   ${YELLOW}make outputs${NC}"
    echo ""
    echo "3. Monitor in Confluent Cloud:"
    echo -e "   ${YELLOW}https://confluent.cloud${NC}"
    echo ""
    echo "4. When done, clean up:"
    echo -e "   ${YELLOW}make destroy${NC}"
    echo ""
}

# Main wizard flow
main() {
    print_banner

    # Check if setup was run
    if [[ ! -f ".env" ]]; then
        echo -e "${YELLOW}First time setup detected!${NC}"
        echo "Running automated setup..."
        ./setup.sh
        source .env
    fi

    # Wizard steps
    select_connector_type

    if [[ "$CONNECTOR_TYPE" == "DATAGEN" ]]; then
        configure_datagen
    elif [[ "$CONNECTOR_TYPE" == "S3_SINK" ]]; then
        configure_s3_sink
    elif [[ "$CONNECTOR_TYPE" == "PIPELINE" ]]; then
        configure_pipeline
    elif [[ "$CONNECTOR_TYPE" == "CUSTOM" ]]; then
        echo -e "${YELLOW}For custom connectors, please edit examples/*.json manually${NC}"
        exit 0
    fi

    select_cloud_provider
    review_configuration

    echo ""
    if prompt_yes_no "Deploy now?" "y"; then
        execute_deployment
        show_results
    else
        echo ""
        echo -e "${BLUE}Configuration saved. To deploy later, run:${NC}"
        echo -e "   ${YELLOW}./terraform-cloud-connector.sh --apply${NC}"
        echo ""
    fi
}

main
