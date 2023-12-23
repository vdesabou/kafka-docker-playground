#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

KEYSTORE="${DIR}/keystore.jks"
if [ ! -f ${KEYSTORE} ]
then
     OLDDIR=$PWD

     log "INFO: the file ${KEYSTORE} file is not present, generating it..."
     cd ${DIR}/../../environment/sasl-ssl/security

     log "🔐 Generate keys and certificates used for SSL"
     docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
     cd ${OLDDIR}
     cp ${DIR}/../../environment/sasl-ssl/security/kafka.broker.keystore.jks ${DIR}/keystore.jks
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Splunk source connector"
playground connector create-or-update --connector splunk-source << EOF
{
               "connector.class": "io.confluent.connect.SplunkHttpSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "splunk-source",
                    "splunk.collector.index.default": "default-index",
                    "splunk.port": "8889",
                    "splunk.ssl.key.store.path": "/tmp/keystore.jks",
                    "splunk.ssl.key.store.password": "confluent",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }
EOF

sleep 5

log "Simulate an application sending data to the connector"
curl -k -X POST https://localhost:8889/services/collector/event -d '{"event":"from curl"}'

sleep 5

log "Verifying topic splunk-source"
playground topic consume --topic splunk-source --min-expected-messages 1 --timeout 60

