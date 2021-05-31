#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

stop_all "$DIR"

AZURE_NAME=pg${USER}wh${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait