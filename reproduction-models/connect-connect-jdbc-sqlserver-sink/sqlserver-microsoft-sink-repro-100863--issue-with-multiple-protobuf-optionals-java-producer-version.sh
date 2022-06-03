#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/sqljdbc_7.4/enu/mssql-jdbc-7.4.1.jre8.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-7.4.1.jre8.jar"
     wget https://download.microsoft.com/download/6/9/9/699205CA-F1F1-4DE9-9335-18546C5C8CBD/sqljdbc_7.4.1.0_enu.tar.gz
     tar xvfz sqljdbc_7.4.1.0_enu.tar.gz
     rm -f sqljdbc_7.4.1.0_enu.tar.gz
fi

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.microsoft.repro-100863--issue-with-multiple-protobuf-optionals-java-producer-version.yml"

# log "Register schema for customers_protobuf-value"
# curl -X POST -H "Content-Type: application/json" -d'
# {
#   "schemaType": "PROTOBUF",
#   "schema": "syntax = \"proto3\";\n\npackage server1.dbo.customers;\n\n//doc entry\nmessage Value {\n//doc entry\nint32 field_no_optional = 1;\n//doc entry\noptional string field_first_optional = 2;\n//doc entry\noptional int32 field_second_optional = 3;\n//doc entry\noptional string field_third_optional = 4;\n}"
# }' \
# "http://localhost:8081/subjects/customers_protobuf-value/versions"

# syntax = "proto3";
# package server1.dbo.customers;

# message Value {
#   int32 field_no_optional = 1;
#   optional string field_first_optional = 2;
#   optional int32 field_second_optional = 3;
#   optional string field_third_optional = 4;
# }


log "✨ Run the protobuf java producer which produces to topic customer_protobuf"
docker exec producer-repro-100863 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;selectMethod=cursor",
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
               "batch.size": "10",
               "auto.create": "true",
               "auto.evolve": "true",
               "quote.sql.identifiers": "always",

               "insert.mode":"insert",
               "transforms": "FlattenValue,Rename",
               "transforms.FlattenValue.type": "org.apache.kafka.connect.transforms.Flatten$Value",
               "transforms.Rename.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
               "transforms.Rename.renames": "optionalTest.field_no_optional:field_no_optional,optionalTest.field_first_optional:field_first_optional,optionalTest.field_second_optional:field_second_optional,optionalTest.field_third_optional:field_third_optional"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

sleep 5

log "Show content of customer_protobuf table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from customer_protobuf
GO
EOF
cat /tmp/result.log

# firstName                                                                                                                                                                                                                                                        lastName                                                                                                                                                                                                                                                         field_no_optional field_first_optional                                                                                                                                                                                                                                             field_second_optional field_third_optional                                                                                                                                                                                                                                            
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ------------------------------ ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- --------------------- ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# firstName                                                                                                                                                                                                                                                        lastName                                                                                                                                                                                                                                                                                      0 first field optional 0                                                                                                                                                                                                                                                               0 third field optional 0                                                                                                                                                                                                                                          

# (1 rows affected)