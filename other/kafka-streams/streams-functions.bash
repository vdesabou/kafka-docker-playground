#!/bin/bash
# Functions of the Kafka Streams scripts of this folder (sourced after scripts/utils.sh). Not a .sh file: run-tests.sh
# runs every .sh of the folder as an example.

# Builds the application with kafka-streams $KAFKA_CLIENT_TAG (--client-version), skips the example (exit 111) below
# 3.0.0, starts the plaintext environment with the 3 instances running scenario $1, and waits for them to be RUNNING
function start_streams_scenario () {
    export TOPOLOGY="$1"

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

    # the Confluent release of the Avro serde matching the client version: 7.N.0 for 3.N, 8.N.0 for 4.N
    local major minor confluent_version
    major=$(echo "$KAFKA_CLIENT_TAG" | cut -d '.' -f 1)
    minor=$(echo "$KAFKA_CLIENT_TAG" | cut -d '.' -f 2)
    if [ "$major" -ge 4 ]
    then
        confluent_version="$((major + 4)).$minor.0"
    else
        confluent_version="7.$minor.0"
    fi

    # one jar per client version: --client-version rebuilds instead of reusing a jar of another version. 'clean' because
    # an incremental build keeps the classes compiled against the previous version (the sources did not change). No
    # separate mount of target/: 'clean' could not delete a mount point
    if [ ! -f "${DIR}/streams/target/kafka-streams-app-${KAFKA_CLIENT_TAG}-jar-with-dependencies.jar" ]
    then
        log "🏗️ Building the Kafka Streams application with kafka-streams ${KAFKA_CLIENT_TAG} (Avro serde ${confluent_version})"
        build_java_component_with_retry "kafka-streams-app" docker run -i --rm -v "${DIR}/streams":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/../../scripts/settings.xml:/tmp/settings.xml" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-17 mvn -s /tmp/settings.xml -Dkafka.client.tag=$KAFKA_CLIENT_TAG -Dconfluent.version=$confluent_version clean package
    fi

    log "🌊 Starting 3 instances of the Kafka Streams application, scenario ${TOPOLOGY} (config/${TOPOLOGY}.properties)"
    playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

    log "⏳ Waiting for the 3 instances of application streams-${TOPOLOGY} to be RUNNING"
    for container in streams streams2 streams3
    do
        playground container logs --container $container --wait-for-log "Application state transition from REBALANCING to RUNNING" --max-wait 180
    done
}

# The records of a topic as json lines (key, value, offset…), $2: isolation level (read_uncommitted by default)
function consume_json () {
    playground topic consume --topic "$1" --json --max-messages 100000 ${2:+--isolation-level $2} 2> /dev/null
}

# Sum of the latest count of each key of a topic: the number of records counted so far. $2: isolation level
function total_count () {
    consume_json "$1" "$2" | jq -s 'group_by(.key) | map(max_by(.offset).value | tonumber) | add // 0'
}

# Waits until total_count of topic $1 is $2. $3: isolation level
function wait_for_total_count () {
    local topic="$1" expected="$2" isolation="$3" total
    MAX_WAIT=120
    CUR_WAIT=0
    total=$(total_count "$topic" "$isolation")
    while [ "$total" != "$expected" ]
    do
        sleep 10
        CUR_WAIT=$(( CUR_WAIT+10 ))
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ the counts of $topic add up to $total after $MAX_WAIT seconds, expected $expected"
            exit 1
        fi
        total=$(total_count "$topic" "$isolation")
    done
    log "✅ the counts of $topic add up to $total${isolation:+ ($isolation)}"
}

# Waits until a jq filter $2 on the records of topic $1 (as an array, consume_json) returns true, then shows them
function wait_for_records () {
    local topic="$1" filter="$2" description="$3"
    MAX_WAIT=120
    CUR_WAIT=0
    while [ "$(consume_json "$topic" | jq -s "$filter")" != "true" ]
    do
        sleep 5
        CUR_WAIT=$(( CUR_WAIT+5 ))
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ $topic: $description, not true after $MAX_WAIT seconds. Records:"
            consume_json "$topic" | jq -c '{key, value}'
            exit 1
        fi
    done
    log "✅ $topic: $description"
    consume_json "$topic" | jq -c '{key, value}'
}

# Waits for a log line matching $2 (grep) written by one of the containers $3… since timestamp $1, then shows the
# matching lines of that container: container logs survive a restart, so lines written before must not count
function wait_for_log_since () {
    local since="$1" pattern="$2" container
    shift 2
    MAX_WAIT=180
    CUR_WAIT=0
    while true
    do
        for container in "$@"
        do
            if playground container logs --container "$container" --since "$since" --no-follow --grep "$pattern" 2> /dev/null | grep -q .
            then
                playground container logs --container "$container" --since "$since" --no-follow --grep "$pattern" | cut -c1-400 | head -10
                return 0
            fi
        done
        sleep 5
        CUR_WAIT=$(( CUR_WAIT+5 ))
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ no log matching '$pattern' in $* since $since after $MAX_WAIT seconds"
            exit 1
        fi
    done
}

function now () {
    date +%Y-%m-%dT%H:%M:%S
}
