#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "7.9.99"
then
  logwarn "This example uses the log4j2 configuration of the Kafka tools of CP 8+"
  exit 111
fi

# Kerberos ticket expiry of a Kafka GSSAPI client, in minutes instead of a day: the tickets of the principals of the
# example last 3 minutes (modprinc -maxlife on the KDC, nothing changes in environment/kerberos). Kafka logs in again
# at about 80 % of the lifetime (KerberosLogin): with a keytab it always works, with a ticket cache (kinit) it works
# until the renew-until time. Either way the open connections keep working, and the failure shows at the next
# reconnect (connections.max.reauth.ms 0, the default) or at the next re-authentication (connections.max.reauth.ms)
playground start-environment --environment kerberos

KRB_TOPIC="kerberos-expiry"
LIFETIME="3 minutes"
MAXRENEW="6 minutes"

function kdc_admin () {
  run_logged docker exec kdc kadmin.local -q "$1" > /dev/null 2>&1
}

# a file of the client container (the image of connect, with kinit)
function write_client_file () {
  docker exec -i client bash -c "cat > $1"
}

function client_log_count () {
  docker exec client bash -c "grep -c -E -- \"$2\" /tmp/$1.log 2> /dev/null || true"
}

# wait until the log of a client process contains a line
function wait_for_client_line () {
  name="$1"
  line="$2"
  max_wait="$3"
  log "⏳ waiting up to ${max_wait}s for '$line' in the log of $name"
  log_command --polled docker exec client grep -c -E -- "$line" "/tmp/$name.log"
  cur_wait=0
  while [ "$(client_log_count "$name" "$line")" == "0" ]
  do
    sleep 5
    cur_wait=$((cur_wait + 5))
    if [ $cur_wait -ge $max_wait ]
    then
      docker exec client tail -40 "/tmp/$name.log"
      logerror "❌ '$line' not found in the log of $name after ${max_wait}s"
      exit 1
    fi
  done
  docker exec client grep -m 1 -E -- "$line" "/tmp/$name.log" | cut -c1-300
}

# kafka-producer-perf-test prints a "records sent" line every 5 seconds while records are acknowledged
function expect_still_sending () {
  before=$(client_log_count "$1" "records sent")
  sleep 15
  after=$(client_log_count "$1" "records sent")
  if [ "$after" -le "$before" ]
  then
    docker exec client tail -20 "/tmp/$1.log"
    logerror "❌ $1 should still send records on its open connection"
    exit 1
  fi
  log "✅ $1 still sends records on its open connection"
}

function expect_stuck () {
  before=$(client_log_count "$1" "records sent")
  sleep 15
  after=$(client_log_count "$1" "records sent")
  if [ "$after" -gt "$before" ]
  then
    logerror "❌ $1 should not send any record any more"
    exit 1
  fi
  log "✅ $1 sends nothing any more"
}

# a producer at 2 records/s in the background of the client container, logging the Kerberos refresh thread at INFO
function start_producer () {
  name="$1"
  props="$2"
  ccache="$3"
  log "🚀 producer $name ($props)"
  docker exec -d client bash -c "export KRB5CCNAME=${ccache:-/tmp/krb5cc_unused} KAFKA_HEAP_OPTS='-Xmx256m' KAFKA_LOG4J_OPTS=-Dlog4j2.configurationFile=/tmp/kerberos-expiry-log4j2.yaml; \
    exec kafka-producer-perf-test --topic $KRB_TOPIC --num-records 100000 --throughput 2 --record-size 100 --producer.config /tmp/$props > /tmp/$name.log 2>&1"
}

function stop_producers () {
  docker exec client bash -c "pkill -f '[P]roducerPerformance' || true"
}

log "🎫 principals of the example, with tickets of $LIFETIME renewable for $MAXRENEW"
for principal in app_keytab app_cache app_reauth
do
  kdc_admin "add_principal -randkey $principal@TEST.CONFLUENT.IO"
  kdc_admin "modprinc -maxlife \"$LIFETIME\" -maxrenewlife \"$MAXRENEW\" +allow_renewable $principal@TEST.CONFLUENT.IO"
  kdc_admin "ktadd -k /var/lib/secret/$principal.key -norandkey $principal@TEST.CONFLUENT.IO"
  docker exec kdc chmod a+r /var/lib/secret/$principal.key
done
for principal in app_keytab app_cache app_reauth
do
  docker exec client bash -c "kinit -k -t /var/lib/secret/kafka-admin.key admin/for-kafka && kafka-acls --bootstrap-server broker.kerberos-demo.local:9092 --command-config /etc/kafka/command.properties --add --allow-principal User:$principal --producer --topic $KRB_TOPIC" > /dev/null
done
playground topic create --topic $KRB_TOPIC
# the logs of the producers, copied out for playground analyze logs at the end
rm -rf /tmp/kerberos-ticket-expiry /tmp/kerberos-ticket-expiry-report
mkdir -p /tmp/kerberos-ticket-expiry

write_client_file /tmp/kerberos-expiry-log4j2.yaml << 'EOF'
Configuration:
  Appenders:
    Console:
      name: STDERR
      target: SYSTEM_ERR
      PatternLayout:
        Pattern: "[%d] %p %m (%c)%n"
  Loggers:
    Root:
      level: WARN
      AppenderRef:
        - ref: STDERR
    Logger:
      - name: org.apache.kafka.common.security
        level: INFO
      - name: org.apache.kafka.clients.NetworkClient
        level: INFO
EOF
write_client_file /tmp/keytab.properties << 'EOF'
bootstrap.servers=broker.kerberos-demo.local:9092
security.protocol=SASL_PLAINTEXT
sasl.mechanism=GSSAPI
sasl.kerberos.service.name=kafka
sasl.jaas.config=com.sun.security.auth.module.Krb5LoginModule required useKeyTab=true storeKey=true keyTab="/var/lib/secret/app_keytab.key" principal="app_keytab@TEST.CONFLUENT.IO";
EOF
write_client_file /tmp/cache.properties << 'EOF'
bootstrap.servers=broker.kerberos-demo.local:9092
security.protocol=SASL_PLAINTEXT
sasl.mechanism=GSSAPI
sasl.kerberos.service.name=kafka
sasl.jaas.config=com.sun.security.auth.module.Krb5LoginModule required useTicketCache=true;
EOF

log "1️⃣ Keytab (useKeyTab=true): Kafka logs in again by itself before the ticket expires"
start_producer A-keytab keytab.properties
log "2️⃣ Ticket cache (useTicketCache=true): a kinit renewable for $MAXRENEW, Kafka renews it with kinit -R"
run_logged docker exec client bash -c "KRB5CCNAME=/tmp/krb5cc_app_cache kinit -r 6m -k -t /var/lib/secret/app_cache.key app_cache && KRB5CCNAME=/tmp/krb5cc_app_cache klist"
start_producer B-cache cache.properties /tmp/krb5cc_app_cache

wait_for_client_line A-keytab "TGT expires" 60
wait_for_client_line A-keytab "Initiating re-login for app_keytab" 240
expect_still_sending A-keytab

log "4️⃣ The key of app_keytab changes on the KDC (ktadd without -norandkey), its keytab is not redeployed"
kdc_admin "ktadd -k /tmp/app_keytab-new.key app_keytab@TEST.CONFLUENT.IO"
wait_for_client_line A-keytab "LoginException: Checksum failed" 240
wait_for_client_line A-keytab "No TGT found: will try again" 120
expect_still_sending A-keytab

log "2️⃣ The ticket cache reaches its renew-until time: kinit -R fails, the refresh thread of the client exits"
# two ways to end, depending on the jitter of the refresh: kinit -R refused after renew-until, or a last ticket that
# expires in less than the minimum refresh interval (60 s), and an ERROR that blames the clock
TICKET_CACHE_END="Could not renew TGT due to problem running shell command|is in the past: exiting refresh thread"
wait_for_client_line B-cache "$TICKET_CACHE_END" 420
expect_still_sending B-cache

log "2️⃣ A new client on the same ticket cache does not start, once its last ticket has expired"
log_command --polled docker exec client bash -c "KRB5CCNAME=/tmp/krb5cc_app_cache klist -s"
cur_wait=0
while docker exec client bash -c "KRB5CCNAME=/tmp/krb5cc_app_cache klist -s"
do
  sleep 5
  cur_wait=$((cur_wait + 5))
  if [ $cur_wait -ge 120 ]
  then
    logerror "❌ the ticket cache of app_cache should have expired"
    exit 1
  fi
done
set +e
docker exec client bash -c "export KRB5CCNAME=/tmp/krb5cc_app_cache; echo 1 | timeout 60 kafka-console-producer --bootstrap-server broker.kerberos-demo.local:9092 --topic $KRB_TOPIC --producer.config /tmp/cache.properties" > /tmp/kerberos-expiry-new-client.log 2>&1
set -e
if ! grep -q "client is being asked for a password" /tmp/kerberos-expiry-new-client.log
then
  cat /tmp/kerberos-expiry-new-client.log
  logerror "❌ a new client on the expired ticket cache should fail to log in"
  exit 1
fi
grep -m 1 "LoginException" /tmp/kerberos-expiry-new-client.log | cut -c1-300
log "✅ a new client on the expired ticket cache fails to log in"

log "🔁 The broker restarts: both producers must authenticate their new connections, with no valid ticket"
playground container restart -c broker
playground broker health --wait-healthy --max-wait 180
wait_for_client_line B-cache "terminated during authentication" 180
expect_stuck B-cache
# the keytab client lost its principal in the failed re-login: its new connections fail before any authentication
wait_for_client_line A-keytab "Principal could not be determined from Subject" 180
expect_stuck A-keytab
log "🎓 the ticket cache client says 'Firewall blocking Kafka TLS traffic' on a SASL_PLAINTEXT listener, the keytab client 'Principal could not be determined from Subject', and the broker logs nothing"

docker cp client:/tmp/A-keytab.log /tmp/kerberos-ticket-expiry/A-keytab.log > /dev/null
docker cp client:/tmp/B-cache.log /tmp/kerberos-ticket-expiry/B-cache.log > /dev/null
stop_producers

log "3️⃣ connections.max.reauth.ms=60000 on the broker: an open connection authenticates again every minute"
playground container set-environment-variables -c broker --env "KAFKA_CONNECTIONS_MAX_REAUTH_MS: 60000"
playground broker health --wait-healthy --max-wait 180
run_logged docker exec client bash -c "KRB5CCNAME=/tmp/krb5cc_app_reauth kinit -r 6m -k -t /var/lib/secret/app_reauth.key app_reauth && KRB5CCNAME=/tmp/krb5cc_app_reauth klist"
start_producer C-reauth cache.properties /tmp/krb5cc_app_reauth
wait_for_client_line C-reauth "$TICKET_CACHE_END" 480
log "3️⃣ The ticket is expired: the next re-authentication of the open connection fails, no broker restart needed"
wait_for_client_line C-reauth "terminated during authentication" 180
expect_stuck C-reauth
docker cp client:/tmp/C-reauth.log /tmp/kerberos-ticket-expiry/C-reauth.log > /dev/null
stop_producers

log "🔎 What playground analyze logs says about the logs of the three producers"
playground analyze logs -f /tmp/kerberos-ticket-expiry --output-dir /tmp/kerberos-ticket-expiry-report > /tmp/kerberos-expiry-analyze.log 2>&1 || true
for cause in "🎫 Kerberos ticket cache past its renewable lifetime" "🎫 Kerberos keytab out of date (key changed on the KDC)" "🪓 Connection terminated during authentication"
do
  if ! grep -q "$cause" /tmp/kerberos-expiry-analyze.log
  then
    cat /tmp/kerberos-expiry-analyze.log
    logerror "❌ playground analyze logs should report '$cause'"
    exit 1
  fi
  log "✅ playground analyze logs: $cause"
done
log "📄 the logs of the producers: /tmp/kerberos-ticket-expiry, the report: /tmp/kerberos-ticket-expiry-report"
