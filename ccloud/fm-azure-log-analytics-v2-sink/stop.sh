#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

AZURE_NAME=pg${USER}fmlav2${GITHUB_RUN_NUMBER}${TAG_BASE}
AZURE_NAME=${AZURE_NAME//[-._]/}
if [ ${#AZURE_NAME} -gt 24 ]; then
  AZURE_NAME=${AZURE_NAME:0:24}
fi
AZURE_RESOURCE_GROUP=$AZURE_NAME

log "Deleting resource group"
az group delete --name $AZURE_RESOURCE_GROUP --yes --no-wait

if [ -z "$GITHUB_RUN_NUMBER" ]
then
  # the Entra app is only created when not running with CI
  AZURE_APP_NAME=${AZURE_NAME}-fmla-v2-app
  for app_id in $(az ad app list --display-name "$AZURE_APP_NAME" --query "[].appId" -o tsv)
  do
    log "Deleting Entra app $AZURE_APP_NAME ($app_id)"
    az ad app delete --id "$app_id"
  done
fi

maybe_delete_ccloud_environment