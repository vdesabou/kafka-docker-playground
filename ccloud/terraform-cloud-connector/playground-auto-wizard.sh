#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############################################
# Playground Auto Wizard
#
# Interactive wizard for playground run
#
# Usage: playground run -f ccloud/terraform-cloud-connector/playground-auto-wizard.sh
#############################################

log "🧙 Terraform Cloud Connector - Interactive Wizard"
log "=================================================="
log ""

# Check prerequisites
if ! command -v terraform &> /dev/null; then
    log "📦 Installing Terraform..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew tap hashicorp/tap && brew install hashicorp/tap/terraform
    else
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y terraform
    fi
fi

# Get credentials
if [ -z "$CONFLUENT_CLOUD_API_KEY" ]; then
    if [ -f "$DIR/.env" ]; then
        source "$DIR/.env"
    else
        log "⚠️  Confluent Cloud credentials needed:"
        read -p "API Key: " CONFLUENT_CLOUD_API_KEY
        read -s -p "API Secret: " CONFLUENT_CLOUD_API_SECRET
        echo ""
        export CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET
    fi
fi

# Wizard questions
log ""
log "What do you want to create?"
log "1) Test data generator (Datagen)"
log "2) Complete pipeline (Datagen → S3)"
log "3) Custom connector"
read -p "Choice (1-3): " CHOICE

case $CHOICE in
    1)
        CONNECTOR_TYPE="datagen"
        log ""
        read -p "Topic name [pageviews]: " TOPIC
        TOPIC=${TOPIC:-pageviews}

        log ""
        log "Data template:"
        log "1) PAGEVIEWS"
        log "2) ORDERS"
        log "3) USERS"
        read -p "Template (1-3) [1]: " TEMPLATE_CHOICE

        case ${TEMPLATE_CHOICE:-1} in
            1) TEMPLATE="PAGEVIEWS";;
            2) TEMPLATE="ORDERS";;
            3) TEMPLATE="USERS";;
            *) TEMPLATE="PAGEVIEWS";;
        esac
        ;;
    2)
        CONNECTOR_TYPE="pipeline"
        log ""
        read -p "Topic name [pipeline_data]: " TOPIC
        TOPIC=${TOPIC:-pipeline_data}

        if [ -z "$AWS_ACCESS_KEY_ID" ]; then
            log ""
            log "AWS credentials for S3:"
            read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
            read -s -p "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
            echo ""
            export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        fi

        read -p "S3 Bucket [kafka-playground-${USER}]: " S3_BUCKET
        S3_BUCKET=${S3_BUCKET:-kafka-playground-${USER}}
        ;;
    3)
        logerror "Custom connectors: Edit terraform.tfvars manually"
        exit 1
        ;;
    *)
        logerror "Invalid choice"
        exit 1
        ;;
esac

# Cloud selection
log ""
log "Cloud provider:"
log "1) AWS"
log "2) GCP"
log "3) Azure"
read -p "Choice (1-3) [1]: " CLOUD_CHOICE

case ${CLOUD_CHOICE:-1} in
    1) CLOUD="AWS"; REGION="${AWS_REGION:-us-east-1}";;
    2) CLOUD="GCP"; REGION="us-central1";;
    3) CLOUD="AZURE"; REGION="eastus";;
    *) CLOUD="AWS"; REGION="us-east-1";;
esac

# Summary
log ""
log "════════════════════════════════════════"
log "Configuration Summary:"
log "════════════════════════════════════════"
log "  Type:   $CONNECTOR_TYPE"
log "  Cloud:  $CLOUD"
log "  Region: $REGION"
log "  Topic:  $TOPIC"
[ -n "$TEMPLATE" ] && log "  Template: $TEMPLATE"
[ -n "$S3_BUCKET" ] && log "  S3 Bucket: $S3_BUCKET"
log ""

read -p "Deploy now? (y/n) [y]: " DEPLOY
DEPLOY=${DEPLOY:-y}

if [[ ! "$DEPLOY" =~ ^[Yy]$ ]]; then
    log "Cancelled"
    exit 0
fi

# Deploy based on choice
cd "$DIR"

if [ $CONNECTOR_TYPE == "datagen" ]; then
    export CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET
    TOPIC=$TOPIC TEMPLATE=$TEMPLATE CLOUD=$CLOUD REGION=$REGION \
        bash playground-auto-datagen.sh
else
    export CONFLUENT_CLOUD_API_KEY CONFLUENT_CLOUD_API_SECRET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    TOPIC=$TOPIC S3_BUCKET=$S3_BUCKET CLOUD=$CLOUD REGION=$REGION \
        bash playground-auto-pipeline.sh
fi
