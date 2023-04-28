#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.0"; then
    if [[ "$TAG" != *ubi8 ]]
    then
          logwarn "WARN: This can only be run with UBI image or version greater than 6.0.0"
          exit 111
    fi
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# useful script
# https://raw.githubusercontent.com/mapr-demos/mapr-db-60-getting-started/master/mapr_devsandbox_container_setup.sh

log "Installing Mapr Client"

# RHEL
# required deps for mapr-client
docker exec -i --privileged --user root connect  bash -c "chmod a+rw /etc/yum.repos.d/mapr_core.repo"
docker exec -i --privileged --user root connect  bash -c "rpm -i http://mirror.centos.org/centos/7/os/x86_64/Packages/mtools-4.0.18-5.el7.x86_64.rpm"
docker exec -i --privileged --user root connect  bash -c "rpm -i http://mirror.centos.org/centos/7/os/x86_64/Packages/syslinux-4.05-15.el7.x86_64.rpm"

docker exec -i --privileged --user root connect  bash -c "yum -y install --disablerepo='Confluent*' jre-1.8.0-openjdk hostname findutils net-tools"

docker exec -i --privileged --user root connect  bash -c "rpm --import https://package.mapr.com/releases/pub/maprgpg.key && yum -y update --disablerepo='Confluent*' && yum -y install mapr-client.x86_64"

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
# Mapr sink is failing with CP 6.0 UBI8 #91
docker exec -i --privileged --user root connect bash -c "ln -sf /usr/lib/jvm/jre-1.8.0-openjdk /usr/lib/jvm/java-8-openjdk"
set +e
docker exec -i --privileged --user root connect bash -c "alternatives --remove java /usr/lib/jvm/zulu11/bin/java"
# with 7.3.3
docker exec -i --privileged --user root connect bash -c "alternatives --remove java /usr/lib/jvm/java-11-zulu-openjdk/bin/java"
set -e
docker exec -i --privileged --user root connect bash -c "chown -R appuser:appuser /opt/mapr"
set +e
log "It will fail the first time for some reasons.."
docker exec -i --privileged --user root connect bash -c "/opt/mapr/server/configure.sh -secure -N maprdemo.mapr.io -c -C $MAPR_IP -u appuser -g appuser"
docker exec -i --privileged --user root connect bash -c "rm -rf /opt/mapr/conf && cp -R /opt/mapr/conf.new /opt/mapr/conf"
set -e
docker exec -i --privileged --user root connect bash -c "/opt/mapr/server/configure.sh -secure -N maprdemo.mapr.io -c -C $MAPR_IP -u appuser -g appuser"

docker cp mapr:/opt/mapr/conf/ssl_truststore /tmp/ssl_truststore
docker cp /tmp/ssl_truststore connect:/opt/mapr/conf/ssl_truststore
docker exec -i --privileged --user root connect bash -c "chown -R appuser:appuser /opt/mapr"

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

sleep 70

log "Verify data is in Mapr"
docker exec -i mapr bash -c "mapr dbshell" > /tmp/result.log  2>&1 <<-EOF
find /mapr/maprdemo.mapr.io/maprtopic
EOF
cat /tmp/result.log
grep "_id" /tmp/result.log | grep "record1"
grep "_id" /tmp/result.log | grep "record2"
grep "_id" /tmp/result.log | grep "record3"