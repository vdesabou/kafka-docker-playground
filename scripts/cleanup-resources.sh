#!/bin/bash

IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../scripts/utils.sh

no_wait="$1"

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
    az login -u "$AZ_USER" -p "$AZ_PASS" > /dev/null 2>&1
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

log "Cleanup GCP GCS buckets"
KEYFILE="${DIR}/../connect/connect-gcp-gcs-sink/keyfile.json"
PROJECT="vincent-de-saboulin-lab"
set +e
docker rm -f gcloud-config-cleanup-resources
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

for bucket in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gsutil ls)
do
    if [[ $bucket = *kafkadockerplaygroundbucketrunner* ]]
    then
      log "Removing bucket $bucket"
      docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gsutil -m rm -r $bucket
    fi
done

log "Cleanup GCP BQ datasets"
KEYFILE="${DIR}/../connect/connect-gcp-bigquery-sink/keyfile.json"
PROJECT="vincent-de-saboulin-lab"
set +e
docker rm -f gcloud-config-cleanup-resources
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

for dataset in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest bq --project_id "$PROJECT" ls)
do
    if [[ $dataset = *pgrunnerds* ]]
    then
      log "Remove dataset $dataset"
      docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$dataset"
    fi
done

log "Cleanup AWS S3 buckets"
if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

AWS_REGION=$(aws configure get region | tr '\r' '\n')

for bucket in $(aws s3api list-buckets | jq .Buckets[].Name -r)
do
    if [[ $bucket = *kafkadockerplaygroundbucketrunner* ]] || [[ $bucket = *kafkadockerplaygroundfilepulsebucket* ]]
    then
      set +e
      log "Removing bucket $bucket"
      aws s3 rb s3://$bucket --force 
      set -e
    fi
done

log "Cleanup AWS Kinesis streams"
for stream in $(aws kinesis list-streams | jq '.StreamNames[]' -r)
do
    if [[ $stream = *kafka_docker_playground* ]]
    then
      log "Removing stream $stream"
      aws kinesis delete-stream --stream-name $stream
    fi
done