#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


maybe_delete_ccloud_environment

AZURE_NAME=pg${USER}fmfm${GITHUB_RUN_NUMBER}${TAG_BASE}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait