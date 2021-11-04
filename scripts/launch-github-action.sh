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

if [ -z "$GITHUB_TOKEN" ]
then
  logerror "GITHUB_TOKEN is not set !"
  exit 1
fi

log "Calling github action"
curl -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    --request POST \
    "https://api.github.com/repos/vdesabou/kafka-docker-playground/actions/workflows/ci-base.yml/dispatches" \
    -d '{"ref":"master"}'