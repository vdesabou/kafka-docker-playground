#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

singlestore-wait-start() {
  log "Waiting for SingleStore to start..."
  while true; do
      if docker exec singlestore memsql -u root -proot -e "select 1" >/dev/null 2>/dev/null; then
          break
      fi
      log "."
      sleep 0.2
  done
  log "Success!"
}

if [ ! -f ${DIR}/singlestore-jdbc-client-1.0.1.jar ]
then
     # install deps
     log "Getting singlestore-jdbc-client-1.0.1.jar"
     wget https://repo.maven.apache.org/maven2/com/singlestore/singlestore-jdbc-client/1.0.1/singlestore-jdbc-client-1.0.1.jar
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Starting singlestore cluster"
docker start singlestore

singlestore-wait-start

log "Creating 'test' SingleStore database..."
docker exec singlestore memsql -u root -proot -e "create database if not exists test;"

log "Sending messages to topic mytable"
playground topic produce -t mytable --nb-messages 3 --forced-value '{"f1":"value%g"}' << 'EOF'
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

log "Creating Singlestore sink connector"
playground connector create-or-update --connector singlestore-sink  << EOF
{
  "connector.class":"com.singlestore.kafka.SingleStoreSinkConnector",
  "tasks.max":"1",
  "topics":"mytable",
  "connection.ddlEndpoint" : "singlestore:3306",
  "connection.database" : "test",
  "connection.user" : "root",
  "connection.password" : "root"
}
EOF

sleep 10

log "Check data is in Singlestore"
docker exec -i singlestore memsql -u root -proot > /tmp/result.log  2>&1 <<-EOF
use test;
show tables;
select * from mytable;
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log
