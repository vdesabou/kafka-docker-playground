#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

function log() {
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
  echo -e "$YELLOW$@$NC"
}

function logerror() {
  RED='\033[0;31m'
  NC='\033[0m' # No Color
  echo -e "$RED$@$NC"
}

function logwarn() {
  PURPLE='\033[0;35m'
  NC='\033[0m' # No Color
  echo -e "$PURPLE$@$NC"
}

if [ ! -z "$AZ_USER" ] && [ ! -z "$AZ_PASS" ]
then
    log "Logging to Azure using environment variables AZ_USER and AZ_PASS"
    set +e
    az logout
    set -e
    az login -u "$AZ_USER" -p "$AZ_PASS"
else
    log "Logging to Azure using browser"
    az login
fi

log "Cleanup Azure Resource groups"
for group in $(az group list --query [].name --output tsv)
do
  if [[ $group = playgroundrunner* ]]
  then
    if [ ! -z "$GITHUB_RUN_NUMBER" ]
    then
      job=$(echo $GITHUB_RUN_NUMBER | cut -d "." -f 1)
      if [[ $group = playgroundrunner$job* ]]
      then
        log "Skipping current github actions $job"
        continue
      fi
    fi
    log "Deleting resource group $group"
    az group delete --name $group --yes
  fi
done

# remove azure ad apps
for fn in `az ad app list --filter "startswith(displayName, 'playgroundrunner')" --query '[].appId'`
do
  if [ "$fn" == "[" ] || [ "$fn" == "]" ] || [ "$fn" == "[]" ]
  then
    continue
  fi
  app=$(echo "$fn" | tr -d '"')
  app=$(echo "$app" | tr -d ',')
  log "Deleting azure ad app $app"
  az ad app delete --id $app
done