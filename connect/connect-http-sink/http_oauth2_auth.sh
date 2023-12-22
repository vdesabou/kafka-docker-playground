#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.oauth2.yml"


log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
{
    "_meta": {
        "topic": "",
        "key": "",
        "relationships": []
    },
    "nested": {
        "phone": "faker.phone.imei()",
        "website": "faker.internet.domainName()"
    },
    "id": "iteration.index",
    "name": "faker.internet.userName()",
    "email": "faker.internet.exampleEmail()",
    "phone": "faker.phone.imei()",
    "website": "faker.internet.domainName()",
    "city": "faker.address.city()",
    "company": "faker.company.name()"
}
EOF

playground debug log-level set --package "org.apache.http" --level TRACE

log "Set webserver to reply with 200"
curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
# curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time
# curl -X PUT -H "Content-Type: application/json" --data '{"message":"Hello, World!"}' http://localhost:9006/set-response-body

log "Creating http-sink connector"
playground connector create-or-update --connector http-sink << EOF
{
  "topics": "http-messages",
  "tasks.max": "1",
  "connector.class": "io.confluent.connect.http.HttpSinkConnector",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter":"org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable":"false",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1",
  "reporter.bootstrap.servers": "broker:9092",
  "reporter.error.topic.name": "error-responses",
  "reporter.error.topic.replication.factor": 1,
  "reporter.result.topic.name": "success-responses",
  "reporter.result.topic.replication.factor": 1,
  "http.api.url": "http://httpserver:9006",
  "auth.type": "OAUTH2",
  "oauth2.token.url": "http://httpserver:9006/oauth/token",
  "oauth2.client.id": "confidentialApplication",
  "oauth2.client.secret": "topSecret",
  "oauth2.token.property": "accessToken",
  "request.body.format" : "json",
  "headers": "Content-Type: application/json"
}
EOF


sleep 10

# create token, see https://github.com/pedroetb/node-oauth2-server-example#with-client_credentials-grant-1
# token=$(curl -X POST \
#   http://localhost:9006/oauth/token \
#   -H 'Content-Type: application/x-www-form-urlencoded' \
#   -H 'Authorization: Basic Y29uZmlkZW50aWFsQXBwbGljYXRpb246dG9wU2VjcmV0' \
#   -d 'grant_type=client_credentials&scope=any' | jq -r '.accessToken')

# "oauth2.client.auth.mode": "headers"
# [2023-09-17T07:50:23.898Z] POST to /oauth/token
# headers:
# {
#   authorization: 'Basic Y29uZmlkZW50aWFsQXBwbGljYXRpb246dG9wU2VjcmV0',
#   'content-type': 'application/x-www-form-urlencoded',
#   'content-length': '39',
#   host: 'httpserver:9006',
#   connection: 'Keep-Alive',
#   'user-agent': 'Apache-HttpClient/4.5.13 (Java/11.0.20)',
#   'accept-encoding': 'gzip,deflate'
# }
# body:
# { grant_type: 'client_credentials', scope: 'any' }


# "oauth2.client.auth.mode": "url"
# [2023-09-17T07:48:00.625Z] POST to /oauth/token
# headers:
# {
#   'content-type': 'application/x-www-form-urlencoded',
#   'content-length': '97',
#   host: 'httpserver:9006',
#   connection: 'Keep-Alive',
#   'user-agent': 'Apache-HttpClient/4.5.13 (Java/11.0.20)',
#   'accept-encoding': 'gzip,deflate'
# }
# body:
# {
#   grant_type: 'client_credentials',
#   scope: 'any',
#   client_id: 'confidentialApplication',
#   client_secret: 'topSecret'
# }

playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60
