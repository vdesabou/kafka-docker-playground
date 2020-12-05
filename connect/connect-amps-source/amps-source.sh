#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Need to create the AMPS image using https://support.crankuptheamps.com/hc/en-us/articles/360047510833-How-do-I-run-AMPS-in-a-Docker-container-

if [ ! -f ${DIR}/docker-amps/AMPS.tar.gz ]
then
     logerror "ERROR: ${DIR}/docker-amps/ does not contain AMPS tgz file AMPS.tar.gz"
     exit 1
fi

if [ ! -f ${DIR}/amps_client.jar ]
then
     log "${DIR}/amps_client.jar missing, will get it from amps-java-client-5.3.0.1.tar.gz"
     wget https://devnull.crankuptheamps.com/releases/amps/clients/java/5.3.0.1/amps-java-client-5.3.0.1.tar.gz
     tar xvfz amps-java-client-5.3.0.1.tar.gz
     cp ${DIR}/amps-java-client-5.3.0.1/dist/lib/amps_client.jar ${DIR}/
     rm -rf ${DIR}/amps-java-client-5.3.0.1
     rm ${DIR}/amps-java-client-5.3.0.1.tar.gz
fi

if test -z "$(docker images -q amps:latest)"
then
     log "Building AMPS docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-amps
     gunzip -k -f AMPS.tar.gz
     docker build -t amps:latest .
     cd ${OLDDIR}
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Use the spark utility to quickly publish few records to the Orders topic"
docker exec -i amps /AMPS/bin/spark publish -server localhost:9007 -topic Orders -type json << EOF
{"id": 1, "order": "Apples"}
{"id": 2, "order": "Oranges"}
EOF

log "Creating AMPS source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.amps.AmpsSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "AMPS_Orders",
               "amps.servers": "tcp://amps:9007",
               "amps.topic": "Orders",
               "amps.topic.type": "sow",
               "amps.command": "sow_and_subscribe",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/amps-source/config | jq .

sleep 5


log "Verify we have received the data in AMPS_Orders topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic AMPS_Orders --from-beginning --max-messages 2
