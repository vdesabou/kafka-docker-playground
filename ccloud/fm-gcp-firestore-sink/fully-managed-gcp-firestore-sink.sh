#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

GCP_FIRESTORE_DATABASE="pg${USER}fmfd${GITHUB_RUN_NUMBER}${TAG_BASE}"
GCP_FIRESTORE_DATABASE=${GCP_FIRESTORE_DATABASE//[-.]/}
GCP_FIRESTORE_REGION=${1:-europe-west2}
GCP_FIRESTORE_USER_CREDS="${GCP_FIRESTORE_USER_CREDS:-pg-${USER}-fm-firestore}"
GCP_FIRESTORE_USER_CREDS=${GCP_FIRESTORE_USER_CREDS//[-.]/}

if [ -z "$GCP_FIRESTORE_CONNECTION_USER" ]
then
  GCP_FIRESTORE_CONNECTION_USER="$GCP_FIRESTORE_USER_CREDS"
fi

cd ../../ccloud/fm-gcp-firestore-sink
GCP_KEYFILE="${PWD}/keyfile.json"
if [ ! -f ${GCP_KEYFILE} ] && [ -z "$GCP_KEYFILE_CONTENT" ]
then
     logerror "❌ either the file ${GCP_KEYFILE} is not present or environment variable GCP_KEYFILE_CONTENT is not set!"
     exit 1
else 
    if [ -f ${GCP_KEYFILE} ]
    then
        GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
    else
        log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
        echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    fi
fi
cd -

bootstrap_ccloud_environment "gcp" "$GCP_FIRESTORE_REGION"

set +e
playground topic delete --topic products
sleep 3
playground topic create --topic products --nb-partitions 1
set -e


log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

function create_firestore_database_with_retries {
  local max_attempts=${GCP_FIRESTORE_CREATE_MAX_ATTEMPTS:-6}
  local attempt=1
  local create_output=""
  local create_status=0
  local retry_in=""

  while [ $attempt -le $max_attempts ]
  do
    log "Create a Firestore Database (attempt $attempt/$max_attempts)"

    set +e
    create_output=$(docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore databases create --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT --location $GCP_FIRESTORE_REGION --edition=enterprise --enable-mongodb-compatible-data-access 2>&1)
    create_status=$?
    set -e

    if [ $create_status -eq 0 ]
    then
      echo "$create_output"
      return 0
    fi

    echo "$create_output"

    if echo "$create_output" | grep -q "FAILED_PRECONDITION: Database ID"
    then
      retry_in=$(echo "$create_output" | sed -nE 's/.*Please retry in ([0-9]+) seconds.*/\1/p' | tail -1)
      if [ -z "$retry_in" ]
      then
        retry_in=30
      else
        retry_in=$((retry_in + 5))
      fi

      if [ $attempt -lt $max_attempts ]
      then
        logwarn "Firestore database ID is not available yet, retrying in ${retry_in}s"
        sleep $retry_in
        attempt=$((attempt + 1))
        continue
      fi
    fi

    logerror "❌ Firestore database creation failed"
    return $create_status
  done

  logerror "❌ Firestore database creation failed after $max_attempts attempts"
  return 1
}

function firestore_extract_connection_host {
  local raw_value="$1"
  local mongodb_uri=""

  mongodb_uri=$(printf '%s\n' "$raw_value" | tr -d '\r' | grep -o 'mongodb://[^[:space:]]*' | head -1)

  if [ -z "$mongodb_uri" ]
  then
    mongodb_uri=$(printf '%s' "$raw_value" | tr -d '\r')
  fi

  printf '%s\n' "$mongodb_uri" | sed -E 's#^mongodb://([^@/]+@)?([^/?]+).*$#\2#'
}

set +e
log "Deleting Database, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore databases delete --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT << EOF
Y
EOF
set -e
create_firestore_database_with_retries

log "Getting Firestore MongoDB endpoint"
GCP_FIRESTORE_CONNECTION_STRING=$(docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore databases connection-string --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT --auth=none)

if [ -z "$GCP_FIRESTORE_CONNECTION_STRING" ]
then
  logerror "❌ Could not retrieve Firestore MongoDB connection string"
  exit 1
fi

GCP_FIRESTORE_CONNECTION_STRING=$(printf '%s\n' "$GCP_FIRESTORE_CONNECTION_STRING" | tr -d '\r' | grep -o 'mongodb://[^[:space:]]*' | head -1)

if [ -z "$GCP_FIRESTORE_CONNECTION_HOST" ]
then
  GCP_FIRESTORE_CONNECTION_HOST=$(firestore_extract_connection_host "$GCP_FIRESTORE_CONNECTION_STRING")
elif echo "$GCP_FIRESTORE_CONNECTION_HOST" | grep -q '^mongodb://'
then
  GCP_FIRESTORE_CONNECTION_HOST=$(firestore_extract_connection_host "$GCP_FIRESTORE_CONNECTION_HOST")
fi

if [ -z "$GCP_FIRESTORE_CONNECTION_HOST" ]
then
  logerror "❌ Could not parse Firestore MongoDB host from connection string: $GCP_FIRESTORE_CONNECTION_STRING"
  exit 1
fi

if [ -z "$GCP_FIRESTORE_CONNECTION_PASSWORD" ]
then
  log "Creating or rotating Firestore MongoDB user credential for $GCP_FIRESTORE_CONNECTION_USER"
  set +e

  docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore user-creds describe $GCP_FIRESTORE_CONNECTION_USER --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT > /dev/null 2>&1
  user_creds_exists=$?
  set -e

  if [ $user_creds_exists -eq 0 ]
  then
    GCP_FIRESTORE_CONNECTION_PASSWORD=$(docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore user-creds reset-password $GCP_FIRESTORE_CONNECTION_USER --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT --format='value(securePassword)')
  else
    GCP_FIRESTORE_CONNECTION_PASSWORD=$(docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore user-creds create $GCP_FIRESTORE_CONNECTION_USER --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT --format='value(securePassword)')
  fi
fi

if [ -z "$GCP_FIRESTORE_CONNECTION_PASSWORD" ]
then
  logerror "❌ Could not resolve Firestore MongoDB password. Set GCP_FIRESTORE_CONNECTION_PASSWORD and retry"
  exit 1
fi

if [ -z "$GCP_FIRESTORE_CONNECTION_PRINCIPAL" ]
then
  GCP_FIRESTORE_CONNECTION_PRINCIPAL=$(docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore user-creds describe $GCP_FIRESTORE_CONNECTION_USER --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT --format='value(resourceIdentity.principal)')
fi

if [ -z "$GCP_FIRESTORE_CONNECTION_PRINCIPAL" ]
then
  logerror "❌ Could not resolve Firestore MongoDB principal for user $GCP_FIRESTORE_CONNECTION_USER"
  exit 1
fi

log "Granting Firestore read/write IAM role to principal $GCP_FIRESTORE_CONNECTION_PRINCIPAL"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member="$GCP_FIRESTORE_CONNECTION_PRINCIPAL" \
  --role="roles/datastore.user" > /dev/null 2>&1

GCP_FIRESTORE_IAM_PROPAGATION_WAIT_SECONDS=${GCP_FIRESTORE_IAM_PROPAGATION_WAIT_SECONDS:-60}
log "Waiting ${GCP_FIRESTORE_IAM_PROPAGATION_WAIT_SECONDS}s for IAM propagation"
sleep $GCP_FIRESTORE_IAM_PROPAGATION_WAIT_SECONDS

function cleanup_cloud_resources {
  if [ -n "$GCP_FIRESTORE_CONNECTION_PRINCIPAL" ]
  then
    log "Revoking Firestore read/write IAM role from principal $GCP_FIRESTORE_CONNECTION_PRINCIPAL"
    set +e
    docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud projects remove-iam-policy-binding $GCP_PROJECT \
      --member="$GCP_FIRESTORE_CONNECTION_PRINCIPAL" \
      --role="roles/datastore.user" > /dev/null 2>&1
    set -e
  fi

  log "Deleting GCP firestore user creds $GCP_FIRESTORE_CONNECTION_USER"
  set +e
  docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore user-creds delete $GCP_FIRESTORE_CONNECTION_USER --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT << EOF
Y
EOF
  set -e

  log "Deleting GCP firestore database $GCP_FIRESTORE_DATABASE"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud firestore databases delete --database $GCP_FIRESTORE_DATABASE --project $GCP_PROJECT << EOF
Y
EOF
  docker rm -f gcloud-config
}
trap cleanup_cloud_resources EXIT

log "Sending messages to topic products"
playground topic produce -t products --nb-messages 2 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF

playground topic produce -t products --nb-messages 1 --forced-value '{"name": "notebooks", "price": 1.99, "quantity": 5}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF

connector_name="FirestoreSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "FirestoreSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "connection.host": "$GCP_FIRESTORE_CONNECTION_HOST",
  "connection.user": "$GCP_FIRESTORE_CONNECTION_USER",
  "connection.password": "$GCP_FIRESTORE_CONNECTION_PASSWORD",
  "database": "$GCP_FIRESTORE_DATABASE",

  "input.data.format": "AVRO",
  "collection": "kafka_products",
  "topics": "products",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 60

log "Querying collection kafka_products from Firestore MongoDB-compatible endpoint"
docker run --rm -i mongo:7 mongosh "mongodb://$GCP_FIRESTORE_CONNECTION_HOST/$GCP_FIRESTORE_DATABASE?loadBalanced=true&authMechanism=SCRAM-SHA-256&tls=true&retryWrites=false" \
  --username "$GCP_FIRESTORE_CONNECTION_USER" \
  --password "$GCP_FIRESTORE_CONNECTION_PASSWORD" << 'EOF'
db.kafka_products.find().pretty();
EOF

docker run --rm -i mongo:7 mongosh "mongodb://$GCP_FIRESTORE_CONNECTION_HOST/$GCP_FIRESTORE_DATABASE?loadBalanced=true&authMechanism=SCRAM-SHA-256&tls=true&retryWrites=false" \
  --username "$GCP_FIRESTORE_CONNECTION_USER" \
  --password "$GCP_FIRESTORE_CONNECTION_PASSWORD" << EOF > output.txt
db.kafka_products.find().pretty();
EOF
grep "notebooks" output.txt
rm output.txt

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name