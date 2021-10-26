#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

image_versions="$1"
no_wait="$2"

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

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f secrets.properties ]
     then
          logerror "secrets.properties is not present!"
          exit 1
     fi
     source secrets.properties > /dev/null 2>&1
fi

if [ ! -z "$AZ_USER" ] && [ ! -z "$AZ_PASS" ]
then
    log "Logging to Azure using environment variables AZ_USER and AZ_PASS"
    az logout
    az login -u "$AZ_USER" -p "$AZ_PASS"
else
    log "Logging to Azure using browser"
    az login
fi

log "Cleanup Azure Resource groups"
for group in $(az group list --query '[].name' --output tsv)
do
  if [[ $group = pgrunner* ]] || [[ $group = pgec2user* ]]
  then
    if [ ! -z "$GITHUB_RUN_NUMBER" ]
    then
      job=$(echo $GITHUB_RUN_NUMBER | cut -d "." -f 1)
      if [[ $group = pgrunner$job* ]]
      then
        log "Skipping current github actions $job"
        continue
      fi
    fi
    log "Deleting resource group $group"
    az group delete --name $group --yes $no_wait
  fi
done

# remove azure ad apps
for fn in `az ad app list --filter "startswith(displayName, 'pgrunner')" --query '[].appId'`
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

exit 0