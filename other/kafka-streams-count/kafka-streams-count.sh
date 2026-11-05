#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# the application uses KafkaStreams#metadataForLocalThreads() (Kafka Streams 3.0.0)
if ! version_gt $KAFKA_CLIENT_TAG "2.99.99"
then
    logwarn "Kafka Streams $KAFKA_CLIENT_TAG: this example needs Kafka Streams 3.0.0 or later (--client-version)"
    exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
if [ "$PLAYGROUND_ENVIRONMENT" != "plaintext" ]
then
    logwarn "this example only supports the plaintext environment for now (the instances get no client security config)"
    exit 111
fi

# one jar per client version: --client-version rebuilds instead of reusing a jar of another version. 'clean' because an
# incremental build keeps the classes compiled against the previous version (the sources did not change). No separate
# mount of target/: 'clean' could not delete a mount point
if [ ! -f "${DIR}/streams/target/kafka-streams-count-${KAFKA_CLIENT_TAG}-jar-with-dependencies.jar" ]
then
    log "🏗️ Building the Kafka Streams application with kafka-streams ${KAFKA_CLIENT_TAG}"
    build_java_component_with_retry "kafka-streams-count" docker run -i --rm -v "${DIR}/streams":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/../../scripts/settings.xml:/tmp/settings.xml" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-17 mvn -s /tmp/settings.xml -Dkafka.client.tag=$KAFKA_CLIENT_TAG clean package
fi

playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# sum of the latest count of each bucket in the output topic: the number of records counted so far
function total_count () {
    playground topic consume --topic streams-output --json --max-messages 100000 2> /dev/null | jq -s 'group_by(.key) | map(max_by(.offset).value | tonumber) | add // 0'
}

function wait_for_total_count () {
    expected="$1"
    MAX_WAIT=120
    CUR_WAIT=0
    total=$(total_count)
    while [ "$total" != "$expected" ]
    do
        sleep 10
        CUR_WAIT=$(( CUR_WAIT+10 ))
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ the counts of streams-output add up to $total after $MAX_WAIT seconds, expected $expected"
            exit 1
        fi
        total=$(total_count)
    done
    log "✅ the counts of streams-output add up to $total"
}

# waits for a "Restore completed" line written by one of the containers since a timestamp, then shows the restores and
# assignments of that container: container logs survive a restart, so lines written before must not count
function wait_for_restore () {
    since="$1"
    shift
    MAX_WAIT=180
    CUR_WAIT=0
    while true
    do
        for container in "$@"
        do
            if playground container logs --container "$container" --since "$since" --no-follow --grep "Restore completed" 2> /dev/null | grep -q "records restored"
            then
                playground container logs --container "$container" --since "$since" --no-follow --grep "Restore completed\|Assignment of"
                return 0
            fi
        done
        sleep 5
        CUR_WAIT=$(( CUR_WAIT+5 ))
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ no restore logged by $* since $since after $MAX_WAIT seconds"
            exit 1
        fi
    done
}

log "⏳ Waiting for the 3 instances of application streams-count to be RUNNING"
for container in streams streams2 streams3
do
    playground container logs --container $container --wait-for-log "Application state transition from REBALANCING to RUNNING" --max-wait 180
done

log "📤 Producing 1000 records to streams-input (6 partitions)"
playground topic produce --topic streams-input --nb-messages 1000 --value "record-%g" --value-format raw

log "🔢 The application counts them per bucket: groupBy (repartition topic) then count (changelog topic)"
wait_for_total_count 1000

log "👥 Members of the consumer group and their partitions"
playground consumer-group describe --group streams-count --members

log "🔫 Killing instance streams2: its tasks move to streams and streams3, which restore their state from the changelog topic"
killed_at=$(date +%Y-%m-%dT%H:%M:%S)
playground container kill --container streams2

log "📤 Producing 1000 more records while streams2 is down"
playground topic produce --topic streams-input --nb-messages 1000 --value "record-%g" --value-format raw

wait_for_total_count 2000

log "♻️ Restoration of the tasks of streams2 on the remaining instances"
wait_for_restore "$killed_at" streams streams3

log "🔁 Restarting streams2: it first gets standby (warm-up) tasks, then its active tasks back after a follow-up rebalance, and restores their state"
restarted_at=$(date +%Y-%m-%dT%H:%M:%S)
playground container restart --container streams2
wait_for_restore "$restarted_at" streams2

log "📤 Producing 1000 more records with the 3 instances back"
playground topic produce --topic streams-input --nb-messages 1000 --value "record-%g" --value-format raw

wait_for_total_count 3000
