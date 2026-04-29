#!/bin/bash
set -e

#############################################
# Quick Launch Scripts
# One-command deployment for common scenarios
#############################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

function usage() {
    cat << EOF
Usage: $0 [SCENARIO] [OPTIONS]

Quick launch common scenarios with zero configuration!

SCENARIOS:
    datagen         Create cluster with test data generator
    s3              Create cluster with S3 sink (requires AWS creds)
    postgres        Create cluster with PostgreSQL sink
    mongodb         Create cluster with MongoDB sink
    pipeline        Complete pipeline: Datagen → S3
    demo            Full demo: Multi-connector setup

OPTIONS:
    --cloud CLOUD   Cloud provider (AWS, GCP, AZURE) [default: AWS]
    --region REGION Cloud region [default: us-east-1]
    --auto          Auto-approve, no prompts

EXAMPLES:
    # Quick datagen test
    $0 datagen

    # S3 pipeline on GCP
    $0 pipeline --cloud GCP --region us-central1 --auto

    # Full demo with auto-approval
    $0 demo --auto

EOF
}

function check_setup() {
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        echo -e "${YELLOW}Running first-time setup...${NC}"
        "$SCRIPT_DIR/setup.sh"
        source "$SCRIPT_DIR/.env"
    else
        source "$SCRIPT_DIR/.env"
    fi
}

function launch_datagen() {
    echo -e "${BLUE}Launching Datagen cluster...${NC}"

    cat > /tmp/datagen-quick.json << 'EOF'
{
  "connector.class": "DatagenSource",
  "kafka.auth.mode": "SERVICE_ACCOUNT",
  "kafka.topic": "pageviews",
  "quickstart": "PAGEVIEWS",
  "output.data.format": "JSON",
  "tasks.max": "1"
}
EOF

    cd "$SCRIPT_DIR"
    ./terraform-cloud-connector.sh --apply \
        --connector-type DATAGEN \
        --connector-config /tmp/datagen-quick.json \
        --cluster-name "playground-quick-datagen" \
        --cloud "${CLOUD:-AWS}" \
        --region "${REGION:-us-east-1}"

    echo -e "${GREEN}✔ Datagen cluster ready!${NC}"
    terraform output
}

function launch_s3() {
    echo -e "${BLUE}Launching S3 sink cluster...${NC}"

    # Check AWS creds
    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
        echo -e "${YELLOW}AWS credentials required!${NC}"
        read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
        read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
        echo ""
        export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    fi

    S3_BUCKET="${S3_BUCKET:-kafka-playground-${USER}}"

    cat > /tmp/s3-quick.json << EOF
{
  "connector.class": "S3_SINK",
  "kafka.auth.mode": "SERVICE_ACCOUNT",
  "input.data.format": "JSON",
  "topics": "pageviews",
  "s3.bucket.name": "$S3_BUCKET",
  "s3.region": "${AWS_REGION:-us-east-1}",
  "output.data.format": "JSON",
  "time.interval": "HOURLY",
  "flush.size": "1000",
  "tasks.max": "1"
}
EOF

    cd "$SCRIPT_DIR"
    ./terraform-cloud-connector.sh --apply \
        --connector-type S3_SINK \
        --connector-config /tmp/s3-quick.json \
        --cluster-name "playground-quick-s3" \
        --cloud "${CLOUD:-AWS}" \
        --region "${REGION:-us-east-1}"

    echo -e "${GREEN}✔ S3 sink cluster ready!${NC}"
    echo -e "Data will be written to: s3://${S3_BUCKET}/topics/pageviews/"
}

function launch_pipeline() {
    echo -e "${BLUE}Launching complete pipeline (Datagen → S3)...${NC}"

    if [[ -f "$SCRIPT_DIR/examples/complete-pipeline.sh" ]]; then
        cd "$SCRIPT_DIR"
        ./examples/complete-pipeline.sh
    else
        echo "Running manual pipeline setup..."
        launch_datagen
        sleep 30
        launch_s3
    fi

    echo -e "${GREEN}✔ Pipeline ready!${NC}"
    echo "Data flow: Datagen → Kafka → S3"
}

function launch_demo() {
    echo -e "${BLUE}Launching full demo...${NC}"

    cd "$SCRIPT_DIR"

    # Generate multiple example connectors
    if [[ -f "generate-examples.sh" ]]; then
        ./generate-examples.sh
    fi

    # Run Datagen
    launch_datagen

    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}Demo Environment Ready! 🎉${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "Available commands:"
    echo "  make status    - Check connector status"
    echo "  make outputs   - View all outputs"
    echo "  make destroy   - Clean up everything"
}

# Parse arguments
SCENARIO="${1:-}"
shift || true

CLOUD=""
REGION=""
AUTO_APPROVE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --cloud) CLOUD="$2"; shift 2;;
        --region) REGION="$2"; shift 2;;
        --auto) AUTO_APPROVE="yes"; shift;;
        --help) usage; exit 0;;
        *) echo "Unknown option: $1"; usage; exit 1;;
    esac
done

# Main execution
check_setup

case "$SCENARIO" in
    datagen) launch_datagen;;
    s3) launch_s3;;
    postgres) echo "PostgreSQL launch coming soon!"; exit 1;;
    mongodb) echo "MongoDB launch coming soon!"; exit 1;;
    pipeline) launch_pipeline;;
    demo) launch_demo;;
    "") usage; exit 1;;
    *) echo "Unknown scenario: $SCENARIO"; usage; exit 1;;
esac
