#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.2.99"
then
     logwarn "minimal supported connector version is 1.3.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     # vertica.com/client_drivers now redirects to a Rocket Software page: get the same driver version from Maven Central
     log "Getting vertica-jdbc.jar 10.0.1-0 from Maven Central"
     wget -q -O ${DIR}/vertica-jdbc.jar.tmp https://repo1.maven.org/maven2/com/vertica/jdbc/vertica-jdbc/10.0.1-0/vertica-jdbc-10.0.1-0.jar
     mv ${DIR}/vertica-jdbc.jar.tmp ${DIR}/vertica-jdbc.jar
fi


cd ../../connect/connect-vertica-sink

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-vertica/lib/
cp ../../connect/connect-vertica-sink/vertica-jdbc.jar ../../confluent-hub/confluentinc-kafka-connect-vertica/lib/vertica-jdbc.jar
cd -
PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground container logs --container vertica --wait-for-log "Vertica is now running" --max-wait 600
log "VERTICA has started!"

log "Sending messages to topic mytable"
playground topic produce -t mytable --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

log "Creating Vertica sink connector"
playground connector create-or-update --connector vertica-sink  << EOF
{
  "connector.class" : "io.confluent.vertica.VerticaSinkConnector",
  "tasks.max" : "1",
  "vertica.database": "docker",
  "vertica.host": "vertica",
  "vertica.port": "5433",
  "vertica.username": "dbadmin",
  "vertica.password": "",
  "auto.create": "true",
  "auto.evolve": "false",
  "topics": "mytable",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1"
}
EOF

sleep 10

log "Check data is in Vertica"
playground container exec --container vertica --command "/opt/vertica/bin/vsql -hlocalhost -Udbadmin" > /tmp/result.log  2>&1 <<-EOF
select * from mytable;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log
