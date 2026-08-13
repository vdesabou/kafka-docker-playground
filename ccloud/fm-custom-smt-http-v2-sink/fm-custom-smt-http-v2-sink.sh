#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# ---------------------------------------------------------------------------
# Build the kafka-connect-insert-uuid SMT JAR
# ---------------------------------------------------------------------------
UUID_REPO_DIR="$DIR/kafka-connect-insert-uuid"
UUID_JAR="$UUID_REPO_DIR/target/InsertUuid-1.0-SNAPSHOT.jar"

if [ ! -f "$UUID_JAR" ]
then
    if [ ! -d "$UUID_REPO_DIR" ]
    then
        log "Cloning kafka-connect-insert-uuid repository"
        git clone --depth 1 https://github.com/confluentinc/kafka-connect-insert-uuid.git "$UUID_REPO_DIR"
    fi

    log "🏗 Building InsertUuid SMT JAR with Maven (skipping tests)"
    docker run -i --rm \
        -v "$UUID_REPO_DIR":/usr/src/project \
        -v "$HOME/.m2":/root/.m2 \
        -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" \
        -w /usr/src/project \
        maven:3.9.11-eclipse-temurin-17 \
        mvn -s /tmp/settings.xml package -DskipTests > /tmp/insert-uuid-build.log 2>&1
    if [ $? -ne 0 ]
    then
        logerror "❌ Maven build failed"
        tail -100 /tmp/insert-uuid-build.log
        exit 1
    fi
    log "✅ JAR built: $UUID_JAR"
fi

# ---------------------------------------------------------------------------
# Bootstrap Confluent Cloud environment
# ---------------------------------------------------------------------------

bootstrap_ccloud_environment

# ---------------------------------------------------------------------------
# Custom SMT is only available in specific regions.
# Source: https://docs.confluent.io/cloud/current/connectors/configure-custom-single-message-transforms/custom-smt-limitations-support.html
# ---------------------------------------------------------------------------
CLUSTER_CLOUD=$(playground state get ccloud.CLUSTER_CLOUD)
CLUSTER_REGION=$(playground state get ccloud.CLUSTER_REGION)

declare -a CUSTOM_SMT_SUPPORTED_AWS_REGIONS=(
  # Americas
  us-east-1 us-east-2 us-west-2 ca-central-1
  # Europe
  eu-central-1 eu-west-1 eu-west-2
  # Asia Pacific
  ap-east-1 ap-south-1 ap-southeast-1 ap-southeast-2
)
declare -a CUSTOM_SMT_SUPPORTED_AZURE_REGIONS=(
  # Americas
  brazilsouth centralus eastus eastus2 westus2
  # Europe
  germanywestcentral northeurope uksouth westeurope
  # Asia Pacific
  australiaeast centralindia southeastasia
)
declare -a CUSTOM_SMT_SUPPORTED_GCP_REGIONS=(
  # Americas
  us-central1 us-east1 us-east4 us-west4
  # Europe
  europe-west1 europe-west2 europe-west3 europe-west4
  # Asia Pacific
  asia-south1 asia-southeast1 australia-southeast1
)

check_custom_smt_region_support() {
  local cloud="$1"
  local region="$2"
  local -n supported_regions_ref="$3"
  for r in "${supported_regions_ref[@]}"
  do
    if [[ "$r" == "$region" ]]
    then
      return 0
    fi
  done
  return 1
}

case "$CLUSTER_CLOUD" in
  aws)   region_array=CUSTOM_SMT_SUPPORTED_AWS_REGIONS ;;
  azure) region_array=CUSTOM_SMT_SUPPORTED_AZURE_REGIONS ;;
  gcp)   region_array=CUSTOM_SMT_SUPPORTED_GCP_REGIONS ;;
  *)
    logwarn "⚠️ Unknown cloud provider '$CLUSTER_CLOUD', skipping Custom SMT region check"
    region_array=""
    ;;
esac

if [ -n "$region_array" ]
then
  if ! check_custom_smt_region_support "$CLUSTER_CLOUD" "$CLUSTER_REGION" "$region_array"
  then
    logerror "❌ Custom SMT is not supported in $CLUSTER_CLOUD region '$CLUSTER_REGION'"
    logerror "See supported regions: https://docs.confluent.io/cloud/current/connectors/configure-custom-single-message-transforms/custom-smt-limitations-support.html"
    exit 1
  fi
  log "✅ Custom SMT is supported in $CLUSTER_CLOUD region '$CLUSTER_REGION'"
fi

ENVIRONMENT=$(playground state get ccloud.ENVIRONMENT)

# ---------------------------------------------------------------------------
# Upload the custom SMT artifact (idempotent: delete existing one first)
# ---------------------------------------------------------------------------
artifact_name="pg_${USER}_insert_uuid_smt"
artifact_id=""

set +e
artifact_list_file=$(mktemp)
log "Listing existing SMT artifacts (timeout 10s)"
confluent connect artifact list --cloud "$CLUSTER_CLOUD" --environment "$ENVIRONMENT" --output json > "$artifact_list_file" 2>/dev/null &
LIST_PID=$!
( sleep 10 && kill "$LIST_PID" 2>/dev/null ) &
KILLER_PID=$!
wait "$LIST_PID" 2>/dev/null
kill "$KILLER_PID" 2>/dev/null
wait "$KILLER_PID" 2>/dev/null
artifact_list=$(cat "$artifact_list_file" 2>/dev/null)
rm -f "$artifact_list_file"
for row in $(echo "$artifact_list" | jq -r '.[] | @base64' 2>/dev/null)
do
    _jq() { echo "$row" | base64 -d | jq -r "$1"; }
    id=$(_jq '.id')
    name=$(_jq '.display_name // .name')
    if [[ "$name" == "$artifact_name" ]]
    then
        artifact_id="$id"
        log "Deleting existing SMT artifact $artifact_id ($name)"
        confluent connect artifact delete "$artifact_id" --cloud "$CLUSTER_CLOUD" --environment "$ENVIRONMENT" --force
        artifact_id=""
    fi
done
set -e

log "Uploading custom SMT artifact '$artifact_name' to environment $ENVIRONMENT"
output=$(confluent connect artifact create "$artifact_name" \
    --artifact-file "$UUID_JAR" \
    --cloud "$CLUSTER_CLOUD" \
    --description "Insert a UUID field into every record (kafka-connect-insert-uuid)" \
    --environment "$ENVIRONMENT" \
    --output json)
ret=$?
if [ $ret -ne 0 ]
then
    logerror "❌ Failed to create SMT artifact"
    echo "$output"
    exit 1
fi
artifact_id=$(echo "$output" | jq -r '.id')
log "✅ SMT artifact '$artifact_name' uploaded with id $artifact_id"

log "⌛ Waiting for SMT artifact $artifact_id to reach READY state (Confluent scans uploaded JARs)"
MAX_WAIT=120
CUR_WAIT=0
WAIT_INTERVAL=5
while true
do
    artifact_phase=$(confluent connect artifact describe "$artifact_id" \
        --cloud "$CLUSTER_CLOUD" \
        --environment "$ENVIRONMENT" \
        --output json 2>/dev/null | jq -r '.status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    if [[ "$artifact_phase" == "READY" ]]
    then
        log "✅ SMT artifact $artifact_id is READY"
        break
    elif [[ "$artifact_phase" == "FAILED" ]]
    then
        logerror "❌ SMT artifact $artifact_id scan FAILED - the JAR may be incompatible"
        exit 1
    fi
    CUR_WAIT=$(( CUR_WAIT + WAIT_INTERVAL ))
    if [[ "$CUR_WAIT" -ge "$MAX_WAIT" ]]
    then
        logerror "❌ SMT artifact $artifact_id did not reach READY within ${MAX_WAIT}s (current phase: $artifact_phase)"
        exit 1
    fi
    log "⌛ Artifact phase is '$artifact_phase', waiting... (${CUR_WAIT}/${MAX_WAIT}s)"
    sleep $WAIT_INTERVAL
done

connector_name="HttpSinkV2_$USER"

docker compose -f docker-compose.noauth.yml build
docker compose -f docker-compose.noauth.yml down -v --remove-orphans
docker compose -f docker-compose.noauth.yml up -d --quiet-pull

sleep 5

log "Waiting for ngrok to start"
while true
do
  container_id=$(docker ps -q -f name=ngrok)
  if [ -n "$container_id" ]
  then
    status=$(docker inspect --format '{{.State.Status}}' $container_id)
    if [ "$status" = "running" ]
    then
      log "Getting ngrok hostname and port"
      NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
      NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
      NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

      if ! [[ $NGROK_PORT =~ ^[0-9]+$ ]]
      then
        log "NGROK_PORT is not a valid number, keep retrying..."
        continue
      else 
        break
      fi
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done

set +e
playground topic delete --topic http-topic
set -e

log "Creating http-topic topic in Confluent Cloud"
set +e
playground topic create --topic http-topic
set -e

log "Sending messages to topic http-topic"
playground topic produce -t http-topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF


set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
# curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time
# curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

log "Creating fully-managed HTTP V2 Sink connector '$connector_name' with custom InsertUuid SMT $artifact_id"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "HttpSinkV2",
    "name": "$connector_name",
    "topics": "http-topic",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "input.data.format": "AVRO",
    "http.api.base.url": "http://$NGROK_HOSTNAME:$NGROK_PORT",
    "behavior.on.error": "FAIL",
    "apis.num": "1",
    "api1.http.api.path": "/",
    "api1.topics": "http-topic",
    "api1.request.body.format" : "JSON",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",
    "tasks.max" : "1",

    "transforms": "insertuuid",
    "transforms.insertuuid.type": "com.github.cjmatta.kafka.connect.smt.InsertUuid\$Value",
    "transforms.insertuuid.uuid.field.name": "uuid",
    "transforms.insertuuid.custom.smt.artifact.id": "$artifact_id"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 10 --timeout 60

playground container logs --container httpserver --wait-for-log uuid
log "✅ 'uuid' field is present - custom InsertUuid SMT worked correctly!"

log "Do you want to delete the connector '$connector_name' and the SMT artifact '$artifact_name'?"
check_if_continue

playground connector delete --connector $connector_name
confluent connect artifact delete "$artifact_id" \
    --cloud "$CLUSTER_CLOUD" \
    --environment "$ENVIRONMENT" \
    --force