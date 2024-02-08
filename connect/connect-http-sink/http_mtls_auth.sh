#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-http-sink/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.mtls.yml"

log "Sending messages to topic http-messages"
playground topic produce -t http-messages --nb-messages 10 << 'EOF'
%g
EOF

playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-sink connector"
playground connector create-or-update --connector http-mtls-sink  << EOF
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
     "http.api.url": "https://http-service-mtls-auth:8443/api/messages",
     "auth.type": "NONE",
     "ssl.enabled": "true",
     "https.ssl.truststore.location": "/tmp/truststore.http-service-mtls-auth.jks",
     "https.ssl.truststore.type": "JKS",
     "https.ssl.truststore.password": "confluent",
     "https.ssl.keystore.location": "/tmp/keystore.http-service-mtls-auth.jks",
     "https.ssl.keystore.type": "JKS",
     "https.ssl.keystore.password": "confluent",
     "https.ssl.key.password": "confluent",
     "https.ssl.protocol": "TLSv1.2"
}
EOF


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl --cert ./security/http-service-mtls-auth.certificate.pem --key ./security/http-service-mtls-auth.key --tlsv1.2 --cacert ./security/snakeoil-ca-1.crt  -X GET https://localhost:8643/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log

# docker exec connect curl --cert /tmp/http-service-mtls-auth.certificate.pem --key /tmp/http-service-mtls-auth.key --tlsv1.2 --cacert /tmp/snakeoil-ca-1.crt -X GET https://http-service-mtls-auth:8443/api/messages | jq .



