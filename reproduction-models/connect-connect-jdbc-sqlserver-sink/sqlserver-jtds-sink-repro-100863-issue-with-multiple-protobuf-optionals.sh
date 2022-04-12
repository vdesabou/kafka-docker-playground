#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-repro-100863
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds.repro-100863-issue-with-multiple-protobuf-optionals.yml"

log "Creating JDBC SQL Server (with JTDS driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                "tasks.max": "1",
                "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433",
                "connection.user": "sa",
                "connection.password": "Password!",
                "topics": "customer_protobuf",
                "auto.create": "true",
                "auto.evolve": "true",
                "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
                "value.converter.schema.registry.url": "http://schema-registry:8081",
                "value.converter.auto.register.schemas" : "false", 
                "value.converter.schemas.enable" : "false", 
                "value.converter.connect.meta.data" : "false", 
                "value.converter.use.latest.version" : "true", 
                "value.converter.latest.compatibility.strict" : "false",
                "quote.sql.identifiers": "always"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

log "✨ Run the protobuf java producer which produces to topic customer_protobuf"
docker exec producer-repro-100863 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"


# [2022-04-11 13:49:41,197] INFO [sqlserver-sink|task-0] Setting metadata for table "dbo"."customer_protobuf" to Table{name='"dbo"."customer_protobuf"', type=TABLE columns=[Column{'field_second_optional', isPrimaryKey=false, allowsNull=true, sqlType=int}, Column{'field_no_optional', isPrimaryKey=false, allowsNull=true, sqlType=int}, Column{'field_third_optional', isPrimaryKey=false, allowsNull=true, sqlType=varchar}, Column{'field_first_optional', isPrimaryKey=false, allowsNull=true, sqlType=varchar}]} (io.confluent.connect.jdbc.util.TableDefinitions:64)

# 13:49:46 ℹ️ Show content of customer_protobuf table:
# field_no_optional field_first_optional field_second_optional field_third_optional
# ------
# 1 test 2 test2

sleep 5

log "Show content of customer_protobuf table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from customer_protobuf
GO
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log