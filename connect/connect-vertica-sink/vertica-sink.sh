#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/vertica-jdbc.jar ]
then
     # install deps
     log "Getting vertica-jdbc.jar from vertica-client-10.0.1-0.x86_64.tar.gz"
     wget -q https://www.vertica.com/client_drivers/10.0.x/10.0.1-0/vertica-client-10.0.1-0.x86_64.tar.gz
     tar xvfz ${DIR}/vertica-client-10.0.1-0.x86_64.tar.gz
     cp ${DIR}/opt/vertica/java/lib/vertica-jdbc.jar ${DIR}/
     rm -rf ${DIR}/opt
     rm -f ${DIR}/vertica-client-10.0.1-0.x86_64.tar.gz
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground --output-level WARN container logs --container vertica --wait-for-log "Vertica is now running" --max-wait 600
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
docker exec -i vertica /opt/vertica/bin/vsql -hlocalhost -Udbadmin > /tmp/result.log  2>&1 <<-EOF
select * from mytable;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log
