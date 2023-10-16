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
  if [[ $group = pgrunner* ]] || [[ $group = pgec2user* ]] || [[ $group = pgvsaboulin* ]]
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
for fn in `az ad app list --filter "startswith(displayName, 'pg')" --query '[].appId'`
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
GCP_KEYFILE="/tmp/keyfile.json"
log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
PROJECT="vincent-de-saboulin-lab"
set +e
docker rm -f gcloud-config-cleanup-resources
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

for bucket in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gsutil ls)
do
    if [[ $bucket = *kafkadockerplaygroundbucketrunner* ]]
    then
      log "Removing bucket $bucket"
      docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest gsutil -m rm -r $bucket
    fi
done

log "Cleanup GCP BQ datasets"
PROJECT="vincent-de-saboulin-lab"
set +e
docker rm -f gcloud-config-cleanup-resources
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config-cleanup-resources google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

for dataset in $(docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" ls)
do
    if [[ $dataset = *pgrunnerds* ]] || [[ $dataset = *pg*vinc* ]] || [[ $dataset = *pg*vsaboulin* ]]
    then
      log "Remove dataset $dataset"
      docker run -i --volumes-from gcloud-config-cleanup-resources google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" rm -r -f -d "$dataset"
    fi
done

log "Cleanup AWS S3 buckets"
if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
then
     logerror "ERROR: either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
     exit 1
else
    if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
    then
        log "💭 Using environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    else
        if [ -f $HOME/.aws/credentials ]
        then
            logwarn "💭 AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set based on $HOME/.aws/credentials"
            export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' )
            export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' ) 
        fi
    fi
    if [ -z "$AWS_REGION" ]
    then
        AWS_REGION=$(aws configure get region | tr '\r' '\n')
        if [ "$AWS_REGION" == "" ]
        then
            logerror "ERROR: either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
            exit 1
        fi
    fi
fi

log "Cleanup AWS buckets"
for bucket in $(aws s3api list-buckets --region $AWS_REGION | jq .Buckets[].Name -r)
do
    if [[ $bucket = *kafkadockerplaygroundbucketrunner* ]] || [[ $bucket = *kafkadockerplaygroundfilepulsebucket* ]]
    then
      set +e
      log "Removing bucket $bucket"
      aws s3 rb s3://$bucket --force --region $AWS_REGION
      set -e
    fi
done

log "Cleanup AWS Kinesis streams"
for stream in $(aws kinesis list-streams --region $AWS_REGION | jq '.StreamNames[]' -r)
do
    if [[ $stream = *kafka_docker_playground* ]]
    then
      log "Removing stream $stream"
      aws kinesis delete-stream --stream-name $stream --region $AWS_REGION
    fi
done

log "Cleanup AWS Redshift clusters"
for cluster in $(aws redshift describe-clusters --region $AWS_REGION | jq '.Clusters[].ClusterIdentifier' -r)
do
    if [[ $cluster = pg*redshift* ]]
    then
      set +e
      log "Delete AWS Redshift $cluster"
      aws redshift delete-cluster --cluster-identifier $cluster --skip-final-cluster-snapshot --region $AWS_REGION
      log "Delete security group sg$cluster"
      aws ec2 delete-security-group --group-name sg$cluster --region $AWS_REGION
      set -e
    fi
done

set +e 
if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
    bootstrap_ccloud_environment

    # for row in $(confluent api-key list --output json | jq -r '.[] | @base64'); do
    #     _jq() {
    #     echo ${row} | base64 --decode | jq -r ${1}
    #     }
        
    #     key=$(echo $(_jq '.key'))
    #     resource_type=$(echo $(_jq '.resource_type'))

    #     if [[ $resource_type = cloud ]] && [[ "$key" != "$CLOUD_API_KEY" ]]
    #     then
    #       log "deleting cloud api key $key"
    #       confluent api-key delete $key --force
    #     fi
    # done

    for row in $(confluent environment list --output json | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
        }
        
        id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        if [[ $name = pg-sa-* ]]
        then
          log "deleting environment $id ($name)"
          confluent environment delete $id --force
        fi
    done

    for topic in $(confluent kafka topic list)
    do
      log "delete topic $topic"
      confluent kafka topic delete "$topic" --force
    done

    for subject in $(curl -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL/subjects" | jq -r '.[]')
    do
      log "delete subject $subject"
      curl --request DELETE -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL/subjects/$subject"
      curl --request DELETE -u "$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$SCHEMA_REGISTRY_URL/subjects/$subject?permanent=true"
    done

    for row in $(confluent connect cluster list --output json | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
        }
        
        id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        log "deleting connector $id ($name)"
        confluent connect cluster delete $id --force
    done

    for row in $(confluent iam service-account list --output json | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
        }
        
        description=$(echo $(_jq '.description'))
        id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        if [[ $description = *my-java-producer-app* ]] || [[ $description = *ccloud-stack-function* ]]
        then
            log "deleting $id ($description)"
            confluent iam service-account delete $id --force
            if [ $? != 0 ]
            then
              break
            fi
            sleep 5
        fi
    done
fi

#####
## SNOWFLAKE
####
# https://<account_name>.<region_id>.snowflakecomputing.com:443
SNOWFLAKE_URL="https://$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com"

# Create encrypted Private key - keep this safe, do not share!
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -v1 PBE-SHA1-RC4-128 -out /tmp/snowflake_key.p8 -passout pass:confluent && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
# Generate public key from private key. You can share your public key.
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "openssl rsa -in /tmp/snowflake_key.p8 -pubout -out /tmp/snowflake_key.pub -passin pass:confluent && chown -R $(id -u $USER):$(id -g $USER) /tmp/"

RSA_PUBLIC_KEY=$(grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC"|tr -d '\n')
RSA_PRIVATE_KEY=$(grep -v "BEGIN ENCRYPTED PRIVATE KEY" snowflake_key.p8 | grep -v "END ENCRYPTED PRIVATE KEY"|tr -d '\n')

log "Drop warehouses"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF > /tmp/result.log
show warehouses like 'PLAYGROUNDWAREHOUSE%';
EOF

for warehouse in $(cat /tmp/result.log| grep PLAYGROUNDWAREHOUSE | cut -d "|" -f 2 | tr -d ' ')
do
    log "Dropping warehouse $warehouse"
docker run --rm -i -e SNOWSQL_PWD="$SNOWFLAKE_PASSWORD" -e RSA_PUBLIC_KEY="$RSA_PUBLIC_KEY" kurron/snowsql --username $SNOWFLAKE_USERNAME -a $SNOWFLAKE_ACCOUNT_NAME << EOF
DROP WAREHOUSE IF EXISTS $warehouse;
EOF
done

# always exit with success
exit 0
