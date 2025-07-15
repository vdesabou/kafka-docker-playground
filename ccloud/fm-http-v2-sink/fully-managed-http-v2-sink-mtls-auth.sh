#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



docker compose -f docker-compose.mtls-auth.yml build
docker compose -f docker-compose.mtls-auth.yml down -v --remove-orphans
docker compose -f docker-compose.mtls-auth.yml up -d --quiet-pull

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

connector_name="HttpSinkV2_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

cd ../../connect/connect-http-sink/
base64_truststore=$(cat $PWD/security/truststore.http-service-mtls-auth.jks | base64 | tr -d '\n')
base64_keystore=$(cat $PWD/security/keystore.http-service-mtls-auth.jks | base64 | tr -d '\n')
cd -

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "HttpSinkV2",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "http-topic",
  "input.data.format": "AVRO",
  "http.api.base.url": "https://$NGROK_HOSTNAME:$NGROK_PORT",
  "behavior.on.error": "FAIL",
  "apis.num": "1",
  "api1.http.api.path": "/api/messages",
  "api1.topics": "http-topic",
  "api1.request.body.format" : "JSON",
  "api1.http.request.headers": "Content-Type: application/json",
  "api1.test.api": "false",
  "tasks.max" : "1",

  "https.ssl.enabled": "true",
  "https.ssl.truststorefile": "data:text/plain;base64,$base64_truststore",
  "https.ssl.truststore.password": "confluent",
  "https.ssl.keystorefile": "data:text/plain;base64,$base64_keystore",
  "https.ssl.keystore.password": "confluent",
  "https.ssl.key.password": "confluent",
  "https.ssl.protocol": "TLSv1.2",
  "https.host.verifier.enabled": "false"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 10 --timeout 60

sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
cd ../../connect/connect-http-sink/
curl --cert ./security/http-service-mtls-auth.certificate.pem --key ./security/http-service-mtls-auth.key --tlsv1.2 --cacert ./security/snakeoil-ca-1.crt  -X GET https://localhost:8643/api/messages | jq . > /tmp/result.log  2>&1
cd -
cat /tmp/result.log
grep "10" /tmp/result.log


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name