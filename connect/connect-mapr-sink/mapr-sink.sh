#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Installing Mapr Client"
if [[ "$TAG" == *ubi8 ]]
then
     # RHEL
     # required deps for mapr-client
     docker exec -i --privileged --user root -t connect  bash -c "rpm -i https://rpmfind.net/linux/centos/7.7.1908/os/x86_64/Packages/mtools-4.0.18-5.el7.x86_64.rpm"
     docker exec -i --privileged --user root -t connect  bash -c "rpm -i https://rpmfind.net/linux/centos/7.7.1908/os/x86_64/Packages/syslinux-4.05-15.el7.x86_64.rpm"

     docker exec -i --privileged --user root -t connect  bash -c "yum -y install hostname findutils net-tools"

     docker exec -i --privileged --user root -t connect  bash -c "rpm --import https://package.mapr.com/releases/pub/maprgpg.key && yum -y update && yum -y install mapr-client.x86_64"
else
     logerror "This can only be run with UBI image"
     exit 1
fi

CONNECT_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' connect)
MAPR_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mapr)

log "Login with maprlogin"
docker exec -i mapr bash -c "maprlogin password -user mapr" << EOF
mapr
EOF

log "Create table /mapr/maprdemo.mapr.io/maprtopic"
docker exec -i mapr bash -c "mapr dbshell" << EOF
create /mapr/maprdemo.mapr.io/maprtopic
EOF

log "Set MAPR_EXTERNAL on mapr"
docker exec -i mapr bash -c "sed -i \"s/MAPR_EXTERNAL=.*/MAPR_EXTERNAL=${MAPR_IP}/\" /opt/mapr/conf/env.sh"
docker exec -i mapr bash -c "service mapr-warden restart"

sleep 30

log "Configure Mapr Client"
docker exec -i -t connect bash -c "/opt/mapr/server/configure.sh -N maprdemo.mapr.io -c -C $MAPR_IP:7222 -H mapr -u appuser -g appuser"


log "Sending messages to topic maprtopic"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic maprtopic --property parse.key=true --property key.separator=, << EOF
1,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record1"}}
2,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record2"}}
3,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record3"}}
EOF

log "Creating Mapr sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mapr.db.MapRDbSinkConnector",
               "tasks.max": "1",
               "mapr.table.map.maprtopic" : "/mapr/maprdemo.mapr.io/maprtopic",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "topics": "maprtopic"
          }' \
     http://localhost:8083/connectors/mapr-sink/config | jq .

sleep 10

log "Verify data is in Mapr"
