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

     log "Generate keys and certificates used for SSL"
     ./certs-create.sh  > /dev/null 2>&1

     cd ${OLDDIR}
     cp ${DIR}/../../environment/sasl-ssl/security/kafka.broker.keystore.jks ${DIR}/keystore.jks
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Splunk sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.SplunkHttpSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "splunk-source",
                    "splunk.collector.index.default": "default-index",
                    "splunk.port": "8889",
                    "splunk.ssl.key.store.path": "/tmp/keystore.jks",
                    "splunk.ssl.key.store.password": "confluent",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/splunk-sink/config | jq_docker_cli .

sleep 5

log "Simulate an application sending data to the connector"
curl -k -X POST https://localhost:8889/services/collector/event -d '{"event":"from curl"}'

sleep 5

log "Verifying topic splunk-source"
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic splunk-source --from-beginning --max-messages 1

