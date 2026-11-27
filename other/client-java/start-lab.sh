#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -n "$CLIENT_VERSION" ]
then
     log "📦 CLIENT_VERSION is set: building the client-java lab image with client version $CLIENT_VERSION"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
# only the client-java container (lab target of the Dockerfile: JDK, client jars, labs/ mounted) and the broker.
# In ZooKeeper mode (CP 7.x) the broker does not depend on the zookeeper service (it is a profile), so start it too
ZOOKEEPER_SERVICE=""
if [ -n "$ENABLE_ZOOKEEPER" ]
then
     ZOOKEEPER_SERVICE="--service zookeeper"
fi
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.lab.yml" --service client-java ${ZOOKEEPER_SERVICE}

log "Creating topic orders, the topic of the programs in labs/"
playground topic create --topic orders --nb-partitions 3

log "Running labs/ProducerBasics.java (single-file program, java X.java) against broker:9092"
set +e
producer_output=$(playground container exec -c client-java --command "java -cp \"\$CONFLUENT_HOME/share/java/kafka/*\" ProducerBasics.java broker:9092" 2>&1)
producer_exit=$?
set -e
echo "$producer_output"
if [ $producer_exit -ne 0 ] || echo "$producer_output" | grep -q "^FAILED key="
then
     logerror "❌ ProducerBasics.java failed (exit code $producer_exit)"
     exit 1
fi
nb_acked=$(echo "$producer_output" | grep -c -- "-> partition" || true)
if [ "$nb_acked" -ne 5 ]
then
     logerror "❌ ProducerBasics.java should have 5 acknowledged records, got $nb_acked"
     exit 1
fi

log "Reading them back with labs/LabConsumer.java (group lab-check, stops on its own after 20 seconds, logs with labs/log4j2.xml)"
set +e
consumer_output=$(playground container exec -c client-java --command "java -Dlog4j2.configurationFile=log4j2.xml -cp \"\$CONFLUENT_HOME/share/java/kafka/*\" LabConsumer.java bootstrap.servers=broker:9092 group.id=lab-check x.topic=orders x.run.ms=20000" 2>&1)
consumer_exit=$?
set -e
echo "$consumer_output" | grep "lab.LabConsumer" || true
nb_consumed=$(echo "$consumer_output" | grep -o "closing, consumed [0-9]* records" | grep -o "[0-9]*" | tail -1)
if [ $consumer_exit -ne 0 ] || [ -z "$nb_consumed" ] || [ "$nb_consumed" -lt 5 ]
then
     echo "$consumer_output"
     logerror "❌ LabConsumer.java should have consumed at least 5 records, got ${nb_consumed:-none} (exit code $consumer_exit)"
     exit 1
fi
log "✅ LabConsumer.java consumed $nb_consumed records"

log "Checking the consumer group lab-check committed the offsets"
playground consumer-group describe --group lab-check
