#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     log "Getting vertica-jdbc.jar from vertica-client-9.3.1-0.x86_64.tar.gz"
     wget https://www.vertica.com/client_drivers/9.3.x/9.3.1-0/vertica-client-9.3.1-0.x86_64.tar.gz
     tar xvfz ${DIR}/vertica-client-9.3.1-0.x86_64.tar.gz
     cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
     rm -rf ${DIR}/opt
     rm -f ${DIR}/vertica-client-9.3.1-0.x86_64.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

###
# batch.size = 3000 (default)
###

log "Create the table mytabledefaultbatchsize and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
create table mytabledefaultbatchsize(f1 varchar(20));
EOF

sleep 2

log "Sending messages to topic mytabledefaultbatchsize"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytabledefaultbatchsize --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Creating JDBC Vertica sink connector - default batch.size (3000)"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.vertica.VerticaSinkConnector",
                    "tasks.max" : "1",
                    "vertica.database": "docker",
                    "vertica.host": "vertica",
                    "vertica.port": "5433",
                    "vertica.username": "dbadmin",
                    "vertica.password": "",
                    "topics": "mytabledefaultbatchsize",
                    "errors.tolerance": "all",
                    "errors.deadletterqueue.topic.name": "dlq",
                    "errors.deadletterqueue.topic.replication.factor": "1",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytabledefaultbatchsize;
EOF

log "Check COPY statements in log"
docker exec vertica bash -c 'grep "mytabledefaultbatchsize" /home/dbadmin/docker/catalog/docker/v_docker_node0001_catalog/vertica.log | grep "COPY"'

# 2020-01-16 13:39:57.137 Init Session:7f7aae00e700-a00000000002fd [Session] <INFO> [PQuery] TX:a00000000002fd(v_docker_node0001-65:0x1e) COPY "mytabledefaultbatchsize" FROM local STDIN UNCOMPRESSED NATIVE AUTO returnrejected
# 2020-01-16 13:39:57.142 Init Session:7f7aae00e700-a00000000002fd [Session] <INFO> [Query] TX:a00000000002fd(v_docker_node0001-65:0x1e) COPY "mytabledefaultbatchsize" FROM local STDIN UNCOMPRESSED NATIVE AUTO returnrejected
# 2020-01-16 13:39:57.161 Init Session:7f7aae00e700-a00000000002fd [Session] <INFO> [AutoProj] rerun exec_simple_query("COPY "mytabledefaultbatchsize" FROM local STDIN UNCOMPRESSED NATIVE AUTO returnrejected", 0)

###
# batch.size = 1
###

log "Create the table mytablebatchsizeone and insert data."
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
create table mytablebatchsizeone(f1 varchar(20));
EOF

sleep 2

log "Sending messages to topic mytablebatchsizeone"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mytablebatchsizeone --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Creating JDBC Vertica sink connector - batch.size (1)"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.vertica.VerticaSinkConnector",
                    "tasks.max" : "1",
                    "vertica.database": "docker",
                    "vertica.host": "vertica",
                    "vertica.port": "5433",
                    "vertica.username": "dbadmin",
                    "vertica.password": "",
                    "topics": "mytablebatchsizeone",
                    "batch.size": "1",
                    "errors.tolerance": "all",
                    "errors.deadletterqueue.topic.name": "dlq",
                    "errors.deadletterqueue.topic.replication.factor": "1",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytablebatchsizeone;
EOF

log "Check COPY statements in log"
docker exec vertica bash -c 'grep "mytablebatchsizeone" /home/dbadmin/docker/catalog/docker/v_docker_node0001_catalog/vertica.log | grep "COPY"'

# 2020-01-16 13:40:12.535 Init Session:7f7aae00e700-a0000000000321 [Session] <INFO> [PQuery] TX:a0000000000321(v_docker_node0001-65:0x1e) COPY "mytablebatchsizeone" FROM local STDIN UNCOMPRESSED NATIVE AUTO returnrejected
# 2020-01-16 13:40:12.536 Init Session:7f7aae00e700-a0000000000321 [Session] <INFO> [Query] TX:a0000000000321(v_docker_node0001-65:0x1e) COPY "mytablebatchsizeone" FROM local STDIN UNCOMPRESSED NATIVE AUTO returnrejected
# 2020-01-16 13:40:12.548 Init Session:7f7aae00e700-a0000000000321 [Session] <INFO> [AutoProj] rerun exec_simple_query("COPY "mytablebatchsizeone" FROM local STDIN UNCOMPRESSED NATIVE AUTO returnrejected", 0)