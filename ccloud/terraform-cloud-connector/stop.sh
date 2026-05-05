#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

log "🗑️  Destroying Terraform-managed Confluent Cloud resources..."

cd "$DIR"

if [ -f "terraform.tfstate" ]; then
    ./terraform-cloud-connector.sh --destroy
else
    logwarn "No Terraform state found. Resources may have already been destroyed."
fi

log "✅ Cleanup complete"
