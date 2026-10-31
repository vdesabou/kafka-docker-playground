#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-replication
# it starts its own mdc-plaintext environment (two clusters): run it once, from the plaintext CI job only
if [ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "plaintext" ]
then
    logwarn "the replication lab starts its own mdc-plaintext environment, skipping with ${PLAYGROUND_ENVIRONMENT}"
    exit 111
fi

if ! version_gt $TAG_BASE "7.3.99"
then
    logwarn "the replication lab is written for CP 7.4+ (cluster linking, MirrorMaker 2 offset sync)"
    exit 111
fi

# wait_for_output <description> <max wait in seconds> <expected text> <command…>: runs the command every 5 seconds
# until its output contains the expected text (the output of the last try is in $LAB_OUTPUT)
function wait_for_output () {
    local description="$1"
    local max_wait="$2"
    local expected="$3"
    shift 3
    local cur_wait=0
    while true
    do
        set +e
        LAB_OUTPUT=$("$@" 2>&1 | perl -pe 's/\e\[[0-9;?]*[A-Za-z]//g')
        set -e
        if grep -qF -- "$expected" <<< "$LAB_OUTPUT"
        then
            log "✅ $description (after ${cur_wait}s)"
            return
        fi
        sleep 5
        cur_wait=$(( cur_wait+5 ))
        if [[ "$cur_wait" -gt "$max_wait" ]]
        then
            echo "$LAB_OUTPUT"
            logerror "❌ $description: '$expected' not found after ${max_wait}s"
            exit 1
        fi
    done
}

# kafka-consumer-groups --describe of a group, on one cluster (broker-us or broker-europe)
function describe_group () {
    playground container exec -c "$1" --command "kafka-consumer-groups --bootstrap-server $1:9092 --describe --group $2"
}

log "Step 1: two clusters, one environment"
playground start-environment --environment mdc-plaintext --docker-compose-override-file "${DIR}/docker-compose.mdc-plaintext.replication.yml"
lab_run playground state get run.environment
lab_expect_contains "mdc-plaintext"
lab_run playground status
# no cluster selected: status shows the connectors and topics of each cluster
lab_expect_contains "🌍 Cluster us"
lab_expect_contains "🌍 Cluster europe"
lab_expect_contains "broker-europe"
lab_expect_contains "broker-us"
lab_expect_contains "connect-europe"
lab_expect_contains "connect-us"
lab_run playground container get-properties -c connect-us
lab_expect_contains "bootstrap.servers=broker-us:9092"
lab_run playground container get-properties -c connect-europe
lab_expect_contains "bootstrap.servers=broker-europe:9092"

log "Step 2: pick the cluster with --cluster"
lab_run playground topic list
lab_expect_exit 1
lab_expect_contains "mdc-plaintext runs two clusters: pass --cluster us|europe"
lab_run playground topic create --topic lab_cluster_selector --cluster europe
lab_expect_exit 0
lab_run playground topic list --cluster europe
lab_expect_contains "lab_cluster_selector"
lab_run playground topic list --cluster us
lab_expect_not_contains "lab_cluster_selector"
# the same with the environment variable, for a whole session
lab_run env PLAYGROUND_CLUSTER=europe ${DIR}/../../scripts/cli/playground topic describe --topic lab_cluster_selector
lab_expect_exit 0
lab_expect_contains "lab_cluster_selector"
lab_run playground connector status --cluster us
lab_expect_contains "No"
lab_run playground consumer-group list --cluster europe
lab_expect_exit 0
playground topic delete --topic lab_cluster_selector --cluster europe
lab_run playground broker health --cluster europe
lab_expect_exit 0
lab_expect_contains "cluster is healthy"
lab_run playground broker stop --cluster europe --broker 1 --kill
lab_expect_contains "playground broker start --broker 1 --cluster europe"
lab_run playground broker health --cluster us
lab_expect_exit 0
lab_run playground broker start --cluster europe --broker 1
lab_expect_exit 0
lab_expect_contains "cluster is healthy"

log "Step 3: Replicator connector, europe to us, with offset translation"
seq -f "european_sale_%g" 20 | playground container exec -c broker-europe --command "kafka-console-producer --bootstrap-server broker-europe:9092 --topic sales_EUROPE"
lab_run playground container exec -c connect-europe --command "ls /usr/share/confluent-hub-components/confluentinc-kafka-connect-replicator/lib | grep -E 'timestamp|interceptor'"
# a consumer with the ConsumerTimestampsInterceptor (jar of the Replicator plugin) reads 10 records
lab_run playground container exec -c connect-europe --command "CLASSPATH=\$(ls /usr/share/confluent-hub-components/confluentinc-kafka-connect-replicator/lib/timestamp-interceptor-*.jar) kafka-console-consumer --bootstrap-server broker-europe:9092 --topic sales_EUROPE --from-beginning --max-messages 10 --group app-with-interceptor --consumer-property interceptor.classes=io.confluent.connect.replicator.offsets.ConsumerTimestampsInterceptor --consumer-property timestamps.topic.replication.factor=1"
lab_expect_contains "Processed a total of 10 messages"
# the same, without the interceptor
lab_run playground container exec -c connect-europe --command "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic sales_EUROPE --from-beginning --max-messages 10 --group app-without-interceptor"
lab_expect_contains "Processed a total of 10 messages"
lab_run playground container exec -c broker-europe --command "kafka-topics --bootstrap-server broker-europe:9092 --list"
lab_expect_contains "__consumer_timestamps"
lab_run describe_group broker-europe app-with-interceptor
lab_expect_contains "app-with-interceptor sales_EUROPE 0 10 20 10"
lab_run playground container exec -c connect-us --command "curl -s -X PUT -H 'Content-Type: application/json' --data @- http://localhost:8083/connectors/replicate-europe-to-us/config" << 'EOF'
{
  "connector.class": "io.confluent.connect.replicator.ReplicatorSourceConnector",
  "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
  "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
  "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
  "src.kafka.bootstrap.servers": "broker-europe:9092",
  "dest.kafka.bootstrap.servers": "broker-us:9092",
  "src.consumer.group.id": "replicate-europe-to-us",
  "topic.whitelist": "sales_EUROPE",
  "provenance.header.enable": "true",
  "offset.translator.batch.period.ms": "5000",
  "confluent.topic.replication.factor": "1"
}
EOF
lab_expect_exit 0
lab_expect_contains "replicate-europe-to-us"
wait_for_output "Replicator task RUNNING" 180 '"state":"RUNNING"' playground container exec -c connect-us --command "curl -s http://localhost:8083/connectors/replicate-europe-to-us/status"
echo "$LAB_OUTPUT"
lab_run playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic sales_EUROPE --from-beginning --max-messages 20 --timeout-ms 120000 --property print.headers=true"
lab_expect_contains "Processed a total of 20 messages"
lab_expect_contains "__replicator_id:"
lab_run playground topic compare --topic sales_EUROPE --from europe --to us --wait
lab_expect_exit 0
lab_expect_contains "sales_EUROPE (us) has as many records as sales_EUROPE (europe) (20)"
wait_for_output "offsets of app-with-interceptor translated in us" 180 "sales_EUROPE" describe_group broker-us app-with-interceptor
echo "$LAB_OUTPUT"
lab_expect_contains "app-with-interceptor sales_EUROPE 0 10 20 10"
lab_run describe_group broker-us app-without-interceptor
lab_expect_contains "GroupIdNotFoundException: Group app-without-interceptor not found."
lab_run playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic sales_EUROPE --max-messages 10 --timeout-ms 60000 --group app-with-interceptor"
lab_expect_contains "Processed a total of 10 messages"
lab_expect_contains "european_sale_11"
lab_expect_not_contains "european_sale_10"
lab_run playground container exec -c broker-us --command "kafka-topics --bootstrap-server broker-us:9092 --list"
lab_run playground container exec -c broker-europe --command "kafka-consumer-groups --bootstrap-server broker-europe:9092 --list"

log "Step 4: MirrorMaker 2 (dedicated mode in connect-us), europe to us, with group offset sync"
playground container exec -c connect-us --command "cat > /tmp/mm2.properties" << 'EOF'
clusters = EUROPE, US
EUROPE.bootstrap.servers = broker-europe:9092
US.bootstrap.servers = broker-us:9092
EUROPE->US.enabled = true
EUROPE->US.topics = sales_EUROPE
US->EUROPE.enabled = false
sync.group.offsets.enabled = true
emit.checkpoints.interval.seconds = 5
sync.group.offsets.interval.seconds = 5
refresh.groups.interval.seconds = 5
refresh.topics.interval.seconds = 5
replication.factor = 1
checkpoints.topic.replication.factor = 1
heartbeats.topic.replication.factor = 1
offset-syncs.topic.replication.factor = 1
config.storage.replication.factor = 1
offset.storage.replication.factor = 1
status.storage.replication.factor = 1
EOF
playground container exec -c connect-us --command "nohup connect-mirror-maker /tmp/mm2.properties > /tmp/mm2.log 2>&1 < /dev/null &"
lab_run playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic EUROPE.sales_EUROPE --from-beginning --max-messages 20 --timeout-ms 180000"
lab_expect_contains "Processed a total of 20 messages"
lab_run playground topic compare --topic sales_EUROPE --to-topic EUROPE.sales_EUROPE --from europe --to us
lab_expect_exit 0
lab_expect_contains "EUROPE.sales_EUROPE (us) has as many records as sales_EUROPE (europe) (20)"
wait_for_output "offsets of app-without-interceptor synced by MirrorMaker 2" 240 "EUROPE.sales_EUROPE" describe_group broker-us app-without-interceptor
echo "$LAB_OUTPUT"
sleep 15
# the group was at offset 10 of 20 in europe: MirrorMaker 2 translates it to 1 in us (the closest offset sync is the
# one of the first record), so a consumer that fails over reads european_sale_2 to european_sale_10 a second time
lab_run describe_group broker-us app-without-interceptor
lab_expect_contains "app-without-interceptor EUROPE.sales_EUROPE 0 1 20 19"
lab_run describe_group broker-us app-with-interceptor
lab_expect_contains "app-with-interceptor EUROPE.sales_EUROPE 0 1 20 19"
lab_expect_contains "app-with-interceptor sales_EUROPE 0 20 20 0"
lab_run playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic EUROPE.sales_EUROPE --max-messages 1 --timeout-ms 60000 --group app-without-interceptor"
lab_expect_contains "european_sale_2"
lab_run playground container exec -c broker-us --command "kafka-topics --bootstrap-server broker-us:9092 --list"
lab_expect_contains "EUROPE.checkpoints.internal"
lab_expect_contains "EUROPE.heartbeats"
lab_expect_contains "mm2-configs.EUROPE.internal"
lab_run playground container exec -c broker-europe --command "kafka-topics --bootstrap-server broker-europe:9092 --list"
lab_expect_contains "mm2-offset-syncs.US.internal"
# connect-mirror-maker finds no log4j2 configuration in the image: its log stays almost empty
lab_run playground container exec -c connect-us --command "head -1 /tmp/mm2.log"
lab_expect_contains "Reconfiguration failed: No configuration found"
# [M] so that pkill doesn't match the shell that runs it
playground container exec -c connect-us --command "pkill -f '[M]irrorMaker' || true"

log "Step 5: Cluster Linking, us to europe, with consumer offset sync"
seq -f "us_sale_%g" 20 | playground container exec -c broker-us --command "kafka-console-producer --bootstrap-server broker-us:9092 --topic sales_US"
lab_run playground container exec -c broker-us --command "kafka-console-consumer --bootstrap-server broker-us:9092 --topic sales_US --from-beginning --max-messages 5 --group app-cl"
lab_expect_contains "Processed a total of 5 messages"
playground container exec -c broker-europe --command "cat > /tmp/cl-groups.json" << 'EOF'
{"groupFilters": [{"name": "*", "patternType": "LITERAL", "filterType": "INCLUDE"}]}
EOF
lab_run playground container exec -c broker-europe --command "kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link us-to-europe --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000 --consumer-group-filters-json-file /tmp/cl-groups.json"
lab_expect_exit 0
lab_expect_contains "Cluster link 'us-to-europe' creation successfully completed."
lab_run playground container exec -c broker-europe --command "kafka-mirrors --create --mirror-topic sales_US --link us-to-europe --bootstrap-server broker-europe:9092"
lab_expect_exit 0
lab_expect_contains "Created topic sales_US."
lab_run playground container exec -c broker-europe --command "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic sales_US --from-beginning --max-messages 20 --timeout-ms 60000"
lab_expect_contains "Processed a total of 20 messages"
# the same offsets on both sides: the group is copied, not translated
wait_for_output "offsets of app-cl synced by the cluster link" 120 "sales_US" describe_group broker-europe app-cl
echo "$LAB_OUTPUT"
lab_expect_contains "app-cl sales_US 0 5 20 15"
lab_run playground container exec -c broker-europe --command "kafka-cluster-links --list --link us-to-europe --include-topics --bootstrap-server broker-europe:9092"
lab_expect_contains "link state: 'ACTIVE', topics: [sales_US]"
lab_run bash -c "echo europe_sale_1 | ${DIR}/../../scripts/cli/playground container exec -c broker-europe --command 'kafka-console-producer --bootstrap-server broker-europe:9092 --topic sales_US --producer-property delivery.timeout.ms=15000 --producer-property request.timeout.ms=10000'"
lab_expect_contains "InvalidRequestException: Cannot append records to read-only mirror topic 'sales_US'"
lab_run playground container exec -c broker-europe --command "kafka-mirrors --promote --topics sales_US --bootstrap-server broker-europe:9092"
lab_expect_exit 0
lab_expect_contains "Request for stopping topic sales_US's mirror was successfully scheduled."
wait_for_output "mirror topic sales_US stopped" 60 "State: STOPPED" playground container exec -c broker-europe --command "kafka-mirrors --describe --topics sales_US --bootstrap-server broker-europe:9092"
echo "$LAB_OUTPUT"
lab_run bash -c "echo europe_sale_1 | ${DIR}/../../scripts/cli/playground container exec -c broker-europe --command 'kafka-console-producer --bootstrap-server broker-europe:9092 --topic sales_US'"
lab_expect_exit 0
lab_run playground container exec -c broker-europe --command "kafka-get-offsets --bootstrap-server broker-europe:9092 --topic sales_US"
lab_expect_contains "sales_US:0:21"
lab_run playground container exec -c broker-europe --command "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic sales_US --max-messages 5 --timeout-ms 60000 --group app-cl"
lab_expect_contains "us_sale_6"
lab_expect_not_contains "us_sale_5"
lab_run playground container exec -c broker-europe --command "kafka-cluster-links --bootstrap-server broker-europe:9092 --delete --link us-to-europe"
lab_expect_contains "Cluster link 'us-to-europe' deletion successfully completed."

log "Step 6: Schema Linking, europe to us, into a context"
cat > /tmp/schema-linking-order.avsc << 'EOT'
{ "type": "record", "name": "Order", "namespace": "com.example", "fields": [ {"name": "id", "type": "int"} ] }
EOT
lab_run playground schema register --subject linked-orders-value --cluster europe --schema @/tmp/schema-linking-order.avsc
lab_expect_exit 0
linked_id=$(grep -oE '"id": [0-9]+' <<< "$LAB_OUTPUT" | head -1 | grep -oE '[0-9]+')
lab_run playground schema exporter create --name eu-to-us --cluster europe --subjects "linked-*" --destination-context europe
lab_expect_exit 0
lab_expect_contains "🔗 exporter eu-to-us: RUNNING"
lab_run playground schema compare --from europe --to us --to-context .europe --subject-prefix linked-
lab_expect_exit 0
lab_expect_contains "✅ linked-orders-value: 1 version(s), same schemas and ids"
lab_run playground schema get --id "$linked_id" --cluster us
lab_expect_exit 1
lab_expect_contains "Schema $linked_id not found"
lab_run playground schema get --id "$linked_id" --cluster us --context europe
lab_expect_exit 0
lab_expect_contains ':.europe:linked-orders-value'
lab_run playground schema exporter pause --name eu-to-us --cluster europe
lab_expect_exit 0
lab_run playground schema exporter delete --name eu-to-us --cluster europe
lab_expect_exit 0

log "✅ all the outputs of the page are as expected"
