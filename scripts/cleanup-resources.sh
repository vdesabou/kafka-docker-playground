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

log "Cleanup Azure Resource groups"
for group in $(az group list --query [].name --output tsv)
do
  if [[ $group = playgroundtravis* ]]
  then
    log "Deleting resource group $group"
    az group delete --name $group --yes
  fi
done
