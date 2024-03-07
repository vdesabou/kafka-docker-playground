#!/bin/bash
set -e

function get_3rdparty_file () {
  file="$1"

  if [ -f $file ]
  then
    echo  "$file already present, skipping"
    return
  fi

  set +e
  aws s3 ls s3://kafka-docker-playground/3rdparty/$file > /dev/null 2>&1
  if [ $? -eq 0 ]
  then
      echo "Downloading <s3://kafka-docker-playground/3rdparty/$file> from S3 bucket"
      aws s3 cp --only-show-errors "s3://kafka-docker-playground/3rdparty/$file" .
      if [ $? -eq 0 ]; then
        echo "📄 <s3://kafka-docker-playground/3rdparty/$file> was downloaded from S3 bucket"
      fi
      if [[ "$OSTYPE" == "darwin"* ]]
      then
          # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
          chmod a+rw $file
      else
          # on CI, docker is run as runneradmin user, need to use sudo
          sudo chmod a+rw $file
      fi
  fi
  set -e
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

cd ../../connect/connect-http-source
HTTP_SOURCE_CONNECTOR_ZIP="confluentinc-kafka-connect-http-source-0.2.0-rc-f1cd5ff.zip"
export CONNECTOR_ZIP="$PWD/$HTTP_SOURCE_CONNECTOR_ZIP"

get_3rdparty_file "$HTTP_SOURCE_CONNECTOR_ZIP"

if [ ! -f ${PWD}/$HTTP_SOURCE_CONNECTOR_ZIP ]
then
     logerror "ERROR: ${PWD}/$HTTP_SOURCE_CONNECTOR_ZIP is missing. You must be a Confluent Employee to run this example !"
     exit 1
fi
cd -

source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.oauth2.yml"

log "Creating http-source connector"

playground connector create-or-update --connector http-source  << EOF
{
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.http.HttpSourceConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "url": "http://httpserver:8080/api/messages",
     "topic.name.pattern":"http-topic-\${entityName}",
     "entity.names": "messages",
     "http.offset.mode": "SIMPLE_INCREMENTING",
     "http.initial.offset": "1",
     "auth.type": "oauth2",
     "oauth2.token.url": "http://httpserver:8080/oauth/token",
     "oauth2.client.id": "kc-client",
     "oauth2.client.secret": "kc-secret"
}
EOF

sleep 3

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X POST \
  http://localhost:18080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq -r '.access_token')


log "Send a message to HTTP server"
curl -X PUT \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer ${token}" \
     --data '{"test":"value"}' \
     http://localhost:18080/api/messages | jq .


sleep 2

log "Verify we have received the data in http-topic-messages topic"
playground topic consume --topic http-topic-messages --min-expected-messages 1 --timeout 60
