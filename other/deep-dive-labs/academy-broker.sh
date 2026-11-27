#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of the broker exercises of https://kafka-docker-playground.io/#/academy (a broker that never joins, a broker
# rejected by the controllers, records lost for the partitions of one broker, no controller majority, acks=all and min
# ISR, a producer throttled by a quota, a replication throttle left by a rebalance, a ZooKeeper to KRaft migration
# stopped at phase 3, a compacted topic that keeps its old versions): runs their
# reproduction models (academy/environment-plaintext) and asserts the symptom each exercise is about, then the fix the
# page gives. The fix edits the compose override of the model, as the learner does: the original is put back at the end
lab_require_plaintext
if ! version_gt $TAG_BASE "7.9.99"
then
    logwarn "the broker exercises are about KRaft: CP 8 or later"
    exit 111
fi
models="${DIR}/../../academy/environment-plaintext"

lab_tmp=$(mktemp -d)
cp "$models"/docker-compose.plaintext.repro-*.yml "$lab_tmp/"
trap 'cp "$lab_tmp"/docker-compose.plaintext.repro-*.yml "$models/"; rm -rf "$lab_tmp"' EXIT

function run_model () {
    lab_run bash -c "cd '$models' && bash '$1'"
}

log "Exercise 1: a broker never joins the cluster"
run_model broker-repro-000017-broker-never-joins-duplicate-node-id.sh
lab_expect_contains "❌ containers broker2 and broker3 have the same node id 2"
lab_run playground broker describe
lab_expect_contains "broker2,broker3 ⚠️ same node id"
lab_expect_contains "Observers (brokers):   1,2,2"
lab_run playground container logs -c broker3 --wait-for-log "Unable to register broker 2 because the controller returned error DUPLICATE_BROKER_REGISTRATION" --max-wait 120
lab_expect_exit 0

log "Exercise 1, Step 3: fix the node id, the data folder remembers the old one"
sed -i.bak 's/KAFKA_NODE_ID: 2/KAFKA_NODE_ID: 3/; s/KAFKA_BROKER_ID: 2/KAFKA_BROKER_ID: 3/' "$models/docker-compose.plaintext.repro-000017-broker-never-joins-duplicate-node-id.yml"
rm -f "$models"/*.bak
lab_run playground container recreate
lab_run playground container logs -c broker3 --wait-for-log "Stored node id 2 doesn't match previous node id 3 in /var/lib/kafka/data/meta.properties" --max-wait 120
lab_expect_exit 0
lab_run playground container recreate --fresh-volumes broker3
lab_expect_contains "🧽 removing container broker3 and its anonymous volumes"
lab_run playground broker health --wait-healthy --max-wait 180
lab_expect_contains "✅ all brokers are registered: 1,2,3"
lab_expect_contains "✅ cluster is healthy"

log "Exercise 2: a broker rejected by the controllers"
run_model broker-repro-000018-broker-rejected-inconsistent-cluster-id.sh
lab_expect_contains "❌ broker 3 (container broker3) is not registered"
lab_run playground container logs -c broker3 --wait-for-log "Unexpected error INCONSISTENT_CLUSTER_ID in FETCH response" --max-wait 120
lab_expect_exit 0

log "Exercise 2, Step 3: the cluster id of the data folder"
sed -i.bak "s/CLUSTER_ID: 'q1Sh-9_ISia_zwGINzRvyQ'/CLUSTER_ID: 'MkU3OEVBNTcwNTJENDM2Qk'/" "$models/docker-compose.plaintext.repro-000018-broker-rejected-inconsistent-cluster-id.yml"
rm -f "$models"/*.bak
lab_run playground container recreate
lab_run playground container logs -c broker3 --wait-for-log "Invalid cluster.id in: /var/lib/kafka/data/meta.properties. Expected MkU3OEVBNTcwNTJENDM2Qk, but read q1Sh-9_ISia_zwGINzRvyQ" --max-wait 120
lab_expect_exit 0
lab_run playground container recreate --fresh-volumes broker3
lab_run playground broker health --wait-healthy --max-wait 180
lab_expect_contains "✅ cluster is healthy"

log "Exercise 3: records lost for the partitions of one broker"
run_model broker-repro-000019-not-leader-or-follower-copied-advertised-listeners.sh
# the partitions led by broker 3 depend on the run, and so does the number of records of each one
lab_expect_contains "org.apache.kafka.common.errors.TimeoutException: Expiring"
lab_expect_contains "ms has passed since batch creation"
lab_expect_contains "⚠️ no offsets for partition(s)"
lab_expect_contains "(leader 3)"
lab_run playground broker describe
lab_expect_contains "3   broker2:9092  null  false   broker3 ⚠️ same endpoint as another broker"
lab_run playground broker health
lab_expect_contains "❌ brokers 2, 3 advertise the same endpoint broker2:9092"

log "Exercise 3, Step 3: each broker advertises its own address"
sed -i.bak 's#BROKER://broker2:9092,HOST://localhost:29392#BROKER://broker3:9092,HOST://localhost:29392#' "$models/docker-compose.plaintext.repro-000019-not-leader-or-follower-copied-advertised-listeners.yml"
rm -f "$models"/*.bak
lab_run playground container recreate
lab_run playground broker health --wait-healthy --max-wait 180
lab_expect_contains "✅ cluster is healthy"
lab_run playground topic get-offsets --topic orders
lab_expect_not_contains "no offsets for partition" "every partition answers"

log "Exercise 4: topic creation hangs, produce works"
run_model broker-repro-000020-topic-creation-hangs-produce-works.sh
lab_expect_contains "TOTAL                                      5"
lab_expect_contains "Call(callName=createTopics"
lab_expect_contains "timed out at"
lab_run playground broker health
lab_expect_contains "❌ KRaft quorum lost: 1 of 3 controllers running (controller2, controller3 stopped)"

log "Exercise 4, Step 3: the controllers come back"
lab_run playground container restart -c controller2 -c controller3
lab_run playground broker health --wait-healthy --max-wait 180
lab_expect_contains "✅ cluster is healthy"
lab_run playground topic create --topic refunds --nb-partitions 3 --replication-factor 3
lab_expect_contains "Created topic refunds."

log "Exercise 5: acks=all fails after a broker crash"
run_model broker-repro-000021-acks-all-not-enough-replicas.sh
# the error of the records, not the UnknownHostException of the producer that still tries to reach the stopped broker
lab_expect_contains "record(s) could not be sent to topic payments: org.apache.kafka.common.errors.NotEnoughReplicasException"
lab_run playground broker health
lab_expect_contains "under min.insync.replicas partitions"

log "Exercise 5, Step 3: broker 3 back, then a third replica"
lab_run playground broker start --broker 3
lab_expect_contains "✅ cluster is healthy"
lab_run playground topic produce --topic payments --nb-messages 9 --key "account-%g" --forced-value '{"payment": %g}' --producer-property acks=all
lab_expect_contains "📤 produced 9 records to topic payments"
lab_run playground topic reassign --topic payments --replicas 1,2,3
lab_run playground topic describe --topic payments
lab_expect_contains "Replicas: 1,2,3"

log "Exercise 6: slow, without any error"
run_model broker-repro-000022-slow-producer-no-error-quota.sh
lab_expect_contains "is throttled for"
lab_expect_contains "🚥 the brokers throttled the producer orders-service"
lab_run playground quota get
lab_expect_contains "Quota configs for client-id 'orders-service' are producer_byte_rate=51200.0"

log "Exercise 6, Step 3: without the quota"
lab_run playground quota delete --client-id orders-service --producer-byte-rate
lab_run playground topic produce --topic orders --nb-messages 3000 --record-size 1000 --forced-value '{"order": %g}' --producer-property client.id=orders-service
lab_expect_contains "📤 produced 3000 records to topic orders"
lab_expect_not_contains "🚥 the brokers throttled" "no throttling without the quota"

log "Exercise 7: a restarted broker takes ages to catch up (a replication throttle left by Auto Data Balancer)"
run_model broker-repro-000034-replica-slow-to-catch-up-rebalance-throttle-left.sh
lab_expect_contains "under-replicated partitions"
lab_expect_contains "🐢 replication throttle set: follower.replication.throttled.rate=100000 (98 KB/s) on brokers 1,2,3"
lab_expect_contains "throttled replicas (leader / follower.replication.throttled.replicas) on topics: orders"
lab_expect_contains "👉 under-replicated partitions of those topics catch up at that rate"
lab_run playground broker config get --broker 3
lab_expect_contains "follower.replication.throttled.rate=100000"

log "Exercise 7, Step 3: confluent-rebalancer finish"
lab_run playground container exec -c broker --command "confluent-rebalancer finish --bootstrap-server broker:9092"
lab_expect_contains "The rebalance has completed and throttling has been disabled"
lab_run playground broker health --wait-healthy --max-wait 90
lab_expect_contains "✅ cluster is healthy"
lab_expect_not_contains "🐢" "no replication throttle any more"

log "Exercise 8: ZooKeeper to KRaft migration, the broker refuses to start in migration mode (CP 7.9)"
run_model broker-repro-000035-broker-refuses-migration-mode-zookeeper-to-kraft.sh
lab_expect_contains "❌ no broker is running: broker is restarting"
lab_run playground container logs -c broker --errors
lab_expect_contains "requirement failed: Must have link coordinator enabled during migration."

log "Exercise 8, Step 3: the missing property"
lab_run playground container set-environment-variables -c broker --env "KAFKA_CONFLUENT_CLUSTER_LINK_METADATA_TOPIC_ENABLE: 'true'"
lab_run playground container logs -c kraft-controller --wait-for-log "Completed migration of metadata from ZooKeeper to KRaft" --max-wait 180
lab_run playground topic produce -t orders --nb-messages 5 --forced-value '{"order": %g, "phase": "dual-write"}'
lab_expect_contains "📤 produced 5 records to topic orders"

log "Exercise 9: the compacted topic keeps every old version (the active segment)"
run_model broker-repro-000040-compacted-topic-keeps-old-versions.sh
lab_expect_contains '{"customer":"c1","version":1}'
lab_run playground topic dump-log --topic customer-profiles
lab_expect_contains "15 record(s), offsets 0-14"
lab_expect_contains "🧹 compacted topic, one segment: 00000000000000000000.log is the active segment"

log "Exercise 9, Step 3: a small segment.ms, then one more record"
lab_run playground topic alter --topic customer-profiles --add-config segment.ms=10000,min.cleanable.dirty.ratio=0.01
sleep 12
lab_run playground topic produce --topic customer-profiles --nb-messages 1 --key c1 --value '{"customer":"c1","version":6}' --value-format raw
MAX_WAIT=120
CUR_WAIT=0
until [ "$(playground topic consume --topic customer-profiles 2>/dev/null | grep -c '"version"')" == "4" ]
do
    sleep 10
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ customer-profiles is not compacted to 4 records $MAX_WAIT seconds after the change"
        exit 1
    fi
done
lab_run playground topic consume --topic customer-profiles
lab_expect_contains '{"customer":"c3","version":5}'
lab_expect_not_contains '{"customer":"c3","version":4}' "the old versions are gone"

log "🎉 broker exercises of the academy: every symptom and every fix as on the page"
