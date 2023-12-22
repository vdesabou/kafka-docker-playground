#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if test -z "$(docker images -q pivotal-gemfire:latest)"
then
     # Need to create the docker image using https://github.com/GSSJacky/gemfire-docker
     cd ${DIR}/docker-pivotal-gemfire/
     get_3rdparty_file "pivotal-gemfire.tgz"
     cd -

     if [ ! -f ${DIR}/docker-pivotal-gemfire/pivotal-gemfire.tgz ]
     then
          logerror "ERROR: ${DIR}/docker-pivotal-gemfire/ does not contain file pivotal-gemfire.tgz"
          exit 1
     fi
     log "Building pivotal-gemfire docker image..it can take a while..."
     OLDDIR=$PWD
     cd ${DIR}/docker-pivotal-gemfire
     docker build --build-arg PIVOTAL_GEMFIRE_VERSION=9.15.1 -t pivotal-gemfire:latest .
     cd ${OLDDIR}
fi

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Starting up locator"
docker exec -i pivotal-gemfire sh /opt/pivotal/workdir/startLocator.sh
log "Starting up server1"
docker exec -i pivotal-gemfire sh /opt/pivotal/workdir/startServer1.sh
log "Starting up server2"
docker exec -i pivotal-gemfire sh /opt/pivotal/workdir/startServer2.sh

sleep 8

log "Sending messages to topic input_topic"
playground topic produce -t input_topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
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

log "Creating Pivotal Gemfire sink connector"
playground connector create-or-update --connector pivotal-gemfire-sink << EOF
{
               "connector.class": "io.confluent.connect.pivotal.gemfire.PivotalGemfireSinkConnector",
               "tasks.max": "1",
               "topics": "input_topic",
               "gemfire.locator.host":"pivotal-gemfire",
               "gemfire.locator.port":"10334",
               "gemfire.username":"",
               "gemfire.password":"",
               "gemfire.region":"exampleRegion",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF

sleep 5

log "Check messages received in Pivotal Gemfire"
docker exec -i pivotal-gemfire gfsh  > /tmp/result.log  2>&1 <<-EOF
connect --locator=localhost[10334]
query --query="select * from /exampleRegion"
EOF
cat /tmp/result.log
grep "value1" /tmp/result.log

