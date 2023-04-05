#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

for component in producer consumer
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "create a topic testtopic with 1 partition"
docker exec broker kafka-topics --create --topic testtopic --partitions 1 --replication-factor 1 --bootstrap-server broker:9092

sleep 1

log "Run the Java consumer. Logs are in consumer.log."
docker exec consumer bash -c "java -jar consumer-1.0.0-jar-with-dependencies.jar" > consumer.log 2>&1 &

sleep 5

log "Run the Java producer, only one message is sent"
docker exec producer bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 5

log "Check commit was done (there is no auto-commit, it is set to PER_MESSAGE)"
timeout 30 docker container exec -i connect bash -c 'kafka-console-consumer \
     --bootstrap-server broker:9092 \
     --topic __consumer_offsets \
     --from-beginning \
     --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter"' | grep testtopic-app

# [testtopic-app,testtopic,0]::OffsetAndMetadata(offset=1, leaderEpoch=Optional[0], metadata=, commitTimestamp=1643115099888, expireTimestamp=None)

log "Sleep more than 3 minutes to reach offsets.retention.minutes=3"
sleep 200

# it is still there


log "Now stop consumer"
docker stop consumer

# [2022-01-25 13:08:11,616] INFO [GroupCoordinator 1]: Member my-java-consumer-0f9eb754-e6b4-47b5-954d-3cfa09d53bcd in group testtopic-app has failed, removing it from the group (kafka.coordinator.group.GroupCoordinator)
# [2022-01-25 13:08:11,619] INFO [GroupCoordinator 1]: Preparing to rebalance group testtopic-app in state PreparingRebalance with old generation 1 (__consumer_offsets-31) (reason: removing member my-java-consumer-0f9eb754-e6b4-47b5-954d-3cfa09d53bcd on heartbeat expiration) (kafka.coordinator.group.GroupCoordinator)
# [2022-01-25 13:08:11,620] INFO [GroupCoordinator 1]: Group testtopic-app with generation 2 is now empty (__consumer_offsets-31) (kafka.coordinator.group.GroupCoordinator)

# [2022-01-25 13:12:04,714] INFO [GroupMetadataManager brokerId=1] Group testtopic-app transitioned to Dead in generation 2 (kafka.coordinator.group.GroupMetadataManager)

# still there for some time, but then we get the tombstone:

# [testtopic-app,testtopic,0]::OffsetAndMetadata(offset=1, leaderEpoch=Optional[0], metadata=, commitTimestamp=1643115099888, expireTimestamp=None)
# [testtopic-app,testtopic,0]::NULL

# log "if I restart consumer "
# docker start consumer
# docker exec consumer bash -c "java -jar consumer-1.0.0-jar-with-dependencies.jar" > consumer.log 2>&1 &

               # [2022-01-25 13:12:58,081] INFO [Consumer clientId=my-java-consumer, groupId=testtopic-app] Found no committed offset for partition testtopic-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator)
               # [2022-01-25 13:12:58,092] INFO [Consumer clientId=my-java-consumer, groupId=testtopic-app] Resetting offset for partition testtopic-0 to position FetchPosition{offset=1, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState)


               # in broker logs:


               # [2022-01-25 13:12:55,038] INFO [GroupCoordinator 1]: Dynamic member with unknown member id joins group testtopic-app in Empty state. Created a new member id my-java-consumer-7dfd6962-b848-4383-a596-82f349150d56 and request the member to rejoin with this id. (kafka.coordinator.group.GroupCoordinator)
               # [2022-01-25 13:12:55,041] INFO [GroupCoordinator 1]: Preparing to rebalance group testtopic-app in state PreparingRebalance with old generation 0 (__consumer_offsets-31) (reason: Adding new member my-java-consumer-7dfd6962-b848-4383-a596-82f349150d56 with group instance id None) (kafka.coordinator.group.GroupCoordinator)
               # [2022-01-25 13:12:58,043] INFO [GroupCoordinator 1]: Stabilized group testtopic-app generation 1 (__consumer_offsets-31) with 1 members (kafka.coordinator.group.GroupCoordinator)
               # [2022-01-25 13:12:58,057] INFO [GroupCoordinator 1]: Assignment received from leader my-java-consumer-7dfd6962-b848-4383-a596-82f349150d56 for group testtopic-app for generation 1. The group has 1 members, 0 of which are static. (kafka.coordinator.group.GroupCoordinator)
