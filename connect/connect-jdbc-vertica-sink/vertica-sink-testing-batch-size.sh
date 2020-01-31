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
# From https://www.vertica.com/docs/9.2.x/HTML/Content/Authoring/ConnectingToVertica/ClientJDBC/JDBCFeatureSupport.htm?tocpath=Connecting%20to%20Vertica%7CClient%20Libraries%7CProgramming%20JDBC%20Client%20Applications%7C_____1
#
# Multiple Batch Conversion to COPY Statements
# The Vertica JDBC driver converts all batch inserts into Vertica COPY statements. If you turn off your JDBC connection's AutoCommit property, the JDBC driver uses a single COPY statement to load data from sequential batch inserts which can improve load performance by reducing overhead. See Batch Inserts Using JDBC Prepared Statements for details.

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
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max" : "1",
                    "connection.url": "jdbc:vertica://vertica:5433/docker?user=dbadmin&password=",
                    "auto.create": "true",
                    "topics": "mytabledefaultbatchsize",
                    "errors.tolerance": "all",
                    "errors.deadletterqueue.topic.name": "dlq",
                    "errors.deadletterqueue.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jdbc-vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytabledefaultbatchsize;
EOF

log "Check COPY statements in log"
docker exec vertica bash -c 'grep "mytabledefaultbatchsize" /home/dbadmin/docker/catalog/docker/v_docker_node0001_catalog/vertica.log | grep "COPY"'

# 2020-01-16 12:53:33.536 Init Session:7f9eda3db700-a0000000000300 [Session] <INFO> [Query] TX:a0000000000300(v_docker_node0001-62:0x1e) COPY public.mytabledefaultbatchsize ( f1 ) FROM LOCAL STDIN NATIVE VARCHAR ENFORCELENGTH RETURNREJECTED AUTO NO COMMIT
# 2020-01-16 12:53:33.549 Init Session:7f9eda3db700-a0000000000300 [Session] <INFO> [AutoProj] rerun exec_simple_query("COPY public.mytabledefaultbatchsize ( f1 ) FROM LOCAL STDIN NATIVE VARCHAR ENFORCELENGTH RETURNREJECTED AUTO NO COMMIT", 0)

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
               "connector.class" : "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max" : "1",
                    "connection.url": "jdbc:vertica://vertica:5433/docker?user=dbadmin&password=",
                    "auto.create": "true",
                    "topics": "mytablebatchsizeone",
                    "batch.size": "1",
                    "errors.tolerance": "all",
                    "errors.deadletterqueue.topic.name": "dlq",
                    "errors.deadletterqueue.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/jdbc-vertica-sink/config | jq .

sleep 10

log "Check data is in Vertica"
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin << EOF
select * from mytablebatchsizeone;
EOF

log "Check INSERT statements in log"
docker exec vertica bash -c 'grep "mytablebatchsizeone" /home/dbadmin/docker/catalog/docker/v_docker_node0001_catalog/vertica.log | grep "INSERT"'

# 2020-01-16 12:53:49.037 Init Session:7f9e637fe700-a000000000030d [Session] <INFO> [PQuery] TX:a000000000030d(v_docker_node0001-62:0x2b) INSERT INTO "mytablebatchsizeone"("f1") VALUES(?)
# 2020-01-16 12:53:49.039 Init Session:7f9e637fe700-a000000000030d [Session] <INFO> [BQuery] TX:a000000000030d(v_docker_node0001-62:0x2b) INSERT INTO "mytablebatchsizeone"("f1") VALUES(?)
# 2020-01-16 12:53:49.050 Init Session:7f9e637fe700-a000000000030d [Session] <INFO> [AutoProj] rerun exec_parse_message("INSERT INTO "mytablebatchsizeone"("f1") VALUES('value1')", ...)
# 2020-01-16 12:53:49.050 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value1')'
# 2020-01-16 12:53:49.058 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value2')'
# 2020-01-16 12:53:49.066 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value3')'
# 2020-01-16 12:53:49.074 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value4')'
# 2020-01-16 12:53:49.082 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value5')'
# 2020-01-16 12:53:49.090 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value6')'
# 2020-01-16 12:53:49.097 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value7')'
# 2020-01-16 12:53:49.105 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value8')'
# 2020-01-16 12:53:49.112 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value9')'
# 2020-01-16 12:53:49.119 Init Session:7f9e637fe700-a000000000030d <LOG> @v_docker_node0001: 00000/3316: Executing statement: 'INSERT INTO "mytablebatchsizeone"("f1") VALUES('value10')'