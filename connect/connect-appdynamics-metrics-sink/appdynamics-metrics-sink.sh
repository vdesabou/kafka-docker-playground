#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the machine agent docker image https://github.com/Appdynamics/docker-machine-agent/blob/master/Dockerfile

if [ ! -f ${DIR}/docker-appdynamics-metrics/machine-agent.zip ]
then
     logerror "ERROR: ${DIR}/docker-appdynamics-metrics/ does not contain file machine-agent.zip"
     exit 1
fi

if test -z "$(docker images -q appdynamics-metrics:latest)"
then
     log "Building appdynamics-metrics docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-appdynamics-metrics
     docker build -t appdynamics-metrics:latest .
     cd ${OLDDIR}
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Check logs"
docker exec -i appdynamics-metrics bash -c "cat /opt/appdynamics/machine-agent/logs/machine-agent.log"

log "Sending messages to topic appdynamics-metrics-topic"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic appdynamics-metrics-topic --property value.schema='{"name": "metric","type": "record","fields": [{"name": "name","type": "string"},{"name": "dimensions", "type": {"name": "dimensions", "type": "record", "fields": [{"name": "aggregatorType", "type":"string"}]}},{"name": "values","type": {"name": "values","type": "record","fields": [{"name":"doubleValue", "type": "double"}]}}]}' << EOF
{"name":"Custom Metrics|Tier-1|CPU-Usage", "dimensions":{"aggregatorType":"AVERAGE"},  "values":{"doubleValue":5.639623848362502}}
EOF

log "Creating AppDynamics Metrics sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.appdynamics.metrics.AppDynamicsMetricsSinkConnector",
               "tasks.max": "1",
               "topics": "appdynamics-metrics-topic",
               "machine.agent.host": "http://appdynamics-metrics",
               "machine.agent.port": "8090",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url":"http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.replication.factor": 1,
               "behavior.on.error": "fail",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/appdynamics-metrics-sink/config | jq .

sleep 5


log "Verify we have received the data in AMPS_Orders topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic AMPS_Orders --from-beginning --max-messages 2
