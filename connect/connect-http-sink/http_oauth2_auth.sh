#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.oauth2.yml"


log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
%g
EOF

playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-sink connector"
playground connector create-or-update --connector http-sink << EOF
{
  "topics": "http-messages",
  "tasks.max": "1",
  "connector.class": "io.confluent.connect.http.HttpSinkConnector",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.storage.StringConverter",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1",
  "reporter.bootstrap.servers": "broker:9092",
  "reporter.error.topic.name": "error-responses",
  "reporter.error.topic.replication.factor": 1,
  "reporter.result.topic.name": "success-responses",
  "reporter.result.topic.replication.factor": 1,
  "http.api.url": "http://http-service-oauth2-auth:8080/api/messages",
  "auth.type": "OAUTH2",
  "oauth2.token.url": "http://http-service-oauth2-auth:8080/oauth/token",
  "oauth2.client.id": "kc-client",
  "oauth2.client.secret": "kc-secret"
}
EOF


sleep 10

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X POST \
  http://localhost:10080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq -r '.access_token')


log "Confirm that the data was sent to the HTTP endpoint."
curl -X GET \
    http://localhost:10080/api/messages \
    -H "Authorization: Bearer ${token}" | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log
