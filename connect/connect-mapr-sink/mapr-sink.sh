#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# useful script
# https://raw.githubusercontent.com/mapr-demos/mapr-db-60-getting-started/master/mapr_devsandbox_container_setup.sh

log "Installing Mapr Client"
if [[ "$TAG" == *ubi8 ]]
then
     # RHEL
     # required deps for mapr-client
     docker exec -i --privileged --user root -t connect  bash -c "rpm -i http://mirror.centos.org/centos/7/os/x86_64/Packages/mtools-4.0.18-5.el7.x86_64.rpm"
     docker exec -i --privileged --user root -t connect  bash -c "rpm -i http://mirror.centos.org/centos/7/os/x86_64/Packages/syslinux-4.05-15.el7.x86_64.rpm"

     docker exec -i --privileged --user root -t connect  bash -c "yum -y install hostname findutils net-tools"

     docker exec -i --privileged --user root -t connect  bash -c "rpm --import https://package.mapr.com/releases/pub/maprgpg.key && yum -y update && yum -y install mapr-client.x86_64"
else
     logerror "This can only be run with UBI image"
     exit 1
fi

CONNECT_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' connect)
MAPR_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' mapr)

log "Login with maprlogin on mapr side (mapr)"
docker exec -i mapr bash -c "maprlogin password -user mapr" << EOF
mapr
EOF

log "Create table /mapr/maprdemo.mapr.io/maprtopic"
docker exec -i mapr bash -c "mapr dbshell" << EOF
create /mapr/maprdemo.mapr.io/maprtopic
EOF

sleep 60

log "Configure Mapr Client"
docker exec -i --privileged --user root -t connect bash -c "/opt/mapr/server/configure.sh -secure -N maprdemo.mapr.io -c -C $MAPR_IP:7222 -H mapr -u appuser -g appuser"

docker cp mapr:/opt/mapr/conf/ssl_truststore /tmp/ssl_truststore
docker cp /tmp/ssl_truststore connect:/opt/mapr/conf/ssl_truststore

log "Login with maprlogin on client side (connect)"
docker exec -i connect bash -c "maprlogin password -user mapr" << EOF
mapr
EOF

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
docker exec -i mapr bash -c "mapr dbshell" << EOF
find /mapr/maprdemo.mapr.io/maprtopic
EOF