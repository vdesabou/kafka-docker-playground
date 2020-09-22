#!/bin/bash

set -e

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

log "Calling github action"
curl -H "Accept: application/vnd.github.everest-preview+json" \
    -H "Authorization: token $GH_TOKEN" \
    --request POST \
    --data '{"event_type": "Updating with latest version"}' \
    https://api.github.com/repos/vdesabou/kafka-docker-playground/dispatches