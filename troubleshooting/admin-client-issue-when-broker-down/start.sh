#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in adminclient
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

docker compose down -v --remove-orphans
docker compose build
docker compose up -d

sleep 30

log "run adminclient to check it works"
docker exec adminclient bash -c "java -jar adminclient-${TAG}-jar-with-dependencies.jar"


log "Pausing broker 1"
docker container pause broker1

for((i=0;i<5;i++)); do
  docker exec adminclient bash -c "java -jar adminclient-${TAG}-jar-with-dependencies.jar"
done

# FIXTHIS: 6.1.0

# [2021-03-02 08:53:35,820] INFO [AdminClient clientId=adminclient-1] Metadata update failed (org.apache.kafka.clients.admin.internals.AdminMetadataManager)
# org.apache.kafka.common.errors.TimeoutException: Call(callName=fetchMetadata, deadlineMs=1614675215819, tries=1, nextAllowedTryMs=1614675215920) timed out at 1614675215820 after 1 attempt(s)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting to send the call. Call: fetchMetadata

# 5.5.3

# [2021-03-02 09:00:36,983] INFO Kafka startTimeMs: 1614675636982 (org.apache.kafka.common.utils.AppInfoParser)
# [2021-03-02 09:01:06,989] INFO [AdminClient clientId=adminclient-1] Metadata update failed (org.apache.kafka.clients.admin.internals.AdminMetadataManager)
# org.apache.kafka.common.errors.TimeoutException: Call(callName=fetchMetadata, deadlineMs=1614675666986) timed out at 1614675666987 after 1 attempt(s)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting to send the call.