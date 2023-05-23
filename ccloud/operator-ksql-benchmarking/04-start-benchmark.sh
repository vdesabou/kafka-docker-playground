#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# read configuration files
#
if [ -r ${DIR}/test.properties ]
then
    . ${DIR}/test.properties
else
    logerror "Cannot read configuration file ${DIR}/test.properties"
    exit 1
fi

if [ -r ${DIR}/ccloud-cluster.properties ]
then
    . ${DIR}/ccloud-cluster.properties
else
    logerror "Cannot read configuration file ${APP_HOME}/ccloud-cluster.properties"
    exit 1
fi

verify_installed "kubectl"
verify_installed "helm"

CONFIG_FILE=${DIR}/client.properties
cat << EOF > ${CONFIG_FILE}
bootstrap.servers=${bootstrap_servers}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${cluster_api_key}' password='${cluster_api_secret}';
schema.registry.url=${schema_registry_url}
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=${schema_registry_api_key}:${schema_registry_api_secret}
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
EOF

kubectl cp ${CONFIG_FILE} confluent/connectors-0:/tmp/config

function wait_for_stream_to_finish () {
  stream="$1"
  TMP_DIRECTORY=/tmp/wait_for_stream_to_finish
  rm -rf $TMP_DIRECTORY
  mkdir -p $TMP_DIRECTORY

  TMP_DIRECTORY_FINISHED=$TMP_DIRECTORY/finished
  mkdir -p $TMP_DIRECTORY_FINISHED

  TMP_DIRECTORY_RESULTS=$TMP_DIRECTORY/results
  mkdir -p $TMP_DIRECTORY_RESULTS

  TMP_DIRECTORY_CPU=$TMP_DIRECTORY/cpu
  mkdir -p $TMP_DIRECTORY_CPU

  TMP_DIRECTORY_MEMORY=$TMP_DIRECTORY/memory
  mkdir -p $TMP_DIRECTORY_MEMORY

  TMP_DIRECTORY_CPU_AVERAGE=$TMP_DIRECTORY/cpu_avg
  mkdir -p $TMP_DIRECTORY_CPU_AVERAGE

  TMP_DIRECTORY_MEMORY_AVERAGE=$TMP_DIRECTORY/memory_avg
  mkdir -p $TMP_DIRECTORY_MEMORY_AVERAGE

  counter=0

  for (( i=0; i<$ksql_replicas; i++ ))
  do
    echo "0" > $TMP_DIRECTORY_CPU/$i
    echo "0" > $TMP_DIRECTORY_MEMORY/$i
    echo "0" > $TMP_DIRECTORY_CPU_AVERAGE/$i
    echo "0" > $TMP_DIRECTORY_MEMORY_AVERAGE/$i
  done
  set +e
  MAX_WAIT=3600
  CUR_WAIT=0
  while [[ ! "$(ls -1q $TMP_DIRECTORY_FINISHED | wc -l | sed 's/ //g')" = "${ksql_replicas}" ]]
  do
    log "----------------------------------------------------------"
    for (( i=0; i<$ksql_replicas; i++ ))
    do
      # cpu and memory usage
      current_cpu=$(kubectl top pod ksql-$i --no-headers=true |awk '{print $2}' | sed 's/m$//')
      old_cpu=$(cat $TMP_DIRECTORY_CPU/$i)
      total_cpu=$((old_cpu + current_cpu))
      echo "$total_cpu" > $TMP_DIRECTORY_CPU/$i

      current_memory=$(kubectl top pod ksql-$i --no-headers=true |awk '{print $3}' | sed 's/Mi$//')
      old_memory=$(cat $TMP_DIRECTORY_MEMORY/$i)
      total_memory=$((old_memory + current_memory))
      echo "$total_memory" > $TMP_DIRECTORY_MEMORY/$i

      throughput=$(kubectl exec -i ksql-$i -- curl -s -X "POST" "http://localhost:8088/ksql" \
          -H "Accept: application/vnd.ksql.v1+json" \
          -d $"{
        \"ksql\": \"DESCRIBE EXTENDED ${stream};\",
        \"streamsProperties\": {}
      }" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)messages-per-sec:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')
      messages=$(kubectl exec -i ksql-$i -- curl -s -X "POST" "http://localhost:8088/ksql" \
          -H "Accept: application/vnd.ksql.v1+json" \
          -d $"{
        \"ksql\": \"DESCRIBE EXTENDED ${stream};\",
        \"streamsProperties\": {}
      }" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)total-messages:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')
      # store results in file, as statistics are disappearng for ORDERS_SHIPPED
      if [ "$messages" != "" ]
      then
        echo "$messages" > $TMP_DIRECTORY_RESULTS/$i
      fi

      if [ "$throughput" = "0" ]
      then
        touch $TMP_DIRECTORY_FINISHED/$i
      elif [ "$throughput" = "" ] && [ ! -f $TMP_DIRECTORY_RESULTS/$i ]
      then
        log "ksql-$i|🐌 $stream has not started"
        continue
      elif [ "$throughput" = "" ] && [ -f $TMP_DIRECTORY_RESULTS/$i ]
      then
        log "ksql-$i|statistics are empty"
        touch $TMP_DIRECTORY_FINISHED/$i
      else
        log "ksql-$i|⏳ $stream is processing $throughput msg/s [cpu=$current_cpu,memory=$current_memory]"
      fi
    done

    ((counter=counter+1))

    for (( i=0; i<$ksql_replicas; i++ ))
    do
      total_cpu=$(cat $TMP_DIRECTORY_CPU/$i)
      avg_cpu=$((total_cpu / counter))
      echo "$avg_cpu" > $TMP_DIRECTORY_CPU_AVERAGE/$i

      total_memory=$(cat $TMP_DIRECTORY_MEMORY/$i)
      avg_memory=$((total_memory / counter))
      echo "$avg_memory" > $TMP_DIRECTORY_MEMORY_AVERAGE/$i
    done

    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
      logerror "❗❗❗ ERROR: Please troubleshoot"
      exit 1
    fi
  done
  set -e
}

function throughtput () {
  stream="$1"
  duration="$2"

  TMP_DIRECTORY=/tmp/wait_for_stream_to_finish
  TMP_DIRECTORY_FINISHED=$TMP_DIRECTORY/finished
  TMP_DIRECTORY_CPU_AVERAGE=$TMP_DIRECTORY/cpu_avg
  TMP_DIRECTORY_MEMORY_AVERAGE=$TMP_DIRECTORY/memory_avg

  totalmessages=0
  for (( i=0; i<$ksql_replicas; i++ ))
  do
    MAX_WAIT=600
    CUR_WAIT=0
    messages=""
    while [[ "${messages}" = "" ]]
    do
      messages=$(kubectl exec -i ksql-$i -- curl -s -X "POST" "http://localhost:8088/ksql" \
          -H "Accept: application/vnd.ksql.v1+json" \
          -d $"{
        \"ksql\": \"DESCRIBE EXTENDED ${stream};\",
        \"streamsProperties\": {}
      }" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)total-messages:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')

      # statistics are disappearng for ORDERS_SHIPPED and ORDERPER_PROD_CUST_AGG
      if [ "$messages" = "" ]
      then
        messages=$TMP_DIRECTORY_FINISHED/$i
      fi

      sleep 5
      CUR_WAIT=$(( CUR_WAIT+5 ))
      if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
        logerror "❗❗❗ ERROR: Please troubleshoot"
        exit 1
      fi
    done
    totalmessages=$((totalmessages + messages))
    log "ℹ️ $messages messages processed by instance ksql-$i"
  done

  throughput=$(echo $((orders_iterations / duration)))
  log "🚀 Stream $stream has processed in total $totalmessages messages in $duration seconds. Throughput (based on $orders_iterations input orders)=$throughput msg/s"

  # compute avg cpu and latency
  avg_cpu_total=0
  avg_memory_total=0
  for (( i=0; i<$ksql_replicas; i++ ))
  do
    avg_cpu=$(cat $TMP_DIRECTORY_CPU_AVERAGE/$i)
    avg_memory=$(cat $TMP_DIRECTORY_MEMORY_AVERAGE/$i)
    log "ksql-$i|avg_cpu=${avg_cpu}m, avg_memory=${avg_memory}Mi"
    avg_cpu_total=$((avg_cpu_total + avg_cpu))
    avg_memory_total=$((avg_memory_total + avg_memory))
  done
  avg_cpu_final=$((avg_cpu_total / ksql_replicas))
  avg_memory_final=$((avg_memory_total / ksql_replicas))
  log "Average|avg_cpu=${avg_cpu_final}m, avg_memory=${avg_memory_final} Mi"
}

# make sure to cleanup everything before running another round of tests
log "Executing 05-cleanup-queries.sh script until it succeeds"
./05-cleanup-queries.sh
while [ $? -ne 0 ]
do
    sleep 10
    log "Retrying 05-cleanup-queries.sh"
    ./05-cleanup-queries.sh
done

set +e
log "Delete topic FILTERED_STREAM, if applicable"
kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic FILTERED_STREAM --delete > /dev/null 2>&1
log "Delete topic ENRICHED_O_C, if applicable"
kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ENRICHED_O_C --delete > /dev/null 2>&1
log "Delete topic ENRICHED_O_C_P, if applicable"
kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ENRICHED_O_C_P --delete > /dev/null 2>&1
log "Delete topic ORDERPER_PROD_CUST_AGG, if applicable"
kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ORDERPER_PROD_CUST_AGG --delete > /dev/null 2>&1
log "Delete topic ORDERS_SHIPPED, if applicable"
kubectl exec -it connectors-0 -- kafka-topics --bootstrap-server ${bootstrap_servers} --command-config /tmp/config --topic ORDERS_SHIPPED --delete > /dev/null 2>&1
set -e

log "Create the ksqlDB tables and streams"
kubectl exec -i ksql-0 -- bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/localhost:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://localhost:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE TABLE CUSTOMERS
(
    customerid varchar PRIMARY KEY,
    firstname varchar,
    lastname varchar, gender varchar,
    random_data varchar,
    address struct<street varchar, city varchar, state varchar, zipcode bigint>
)
WITH
    (kafka_topic='customers', value_format='json');

CREATE TABLE PRODUCTS
(
    productid varchar PRIMARY KEY,
    name varchar,
    category varchar,
    description varchar
)
WITH
    (kafka_topic='products', value_format='json');

CREATE STREAM ORDERS
(
    ordertime bigint,
    orderid bigint,
    productid varchar,
    orderunits integer,
    order_category varchar,
    customerid varchar
)
WITH
    (kafka_topic= 'orders', value_format='json', timestamp='ordertime');

CREATE STREAM SHIPMENTS
(
    SHIPMENT_TIME bigint,
    SHIPMENTID bigint,
    orderid bigint,
    productid varchar,
    customerid varchar
)
WITH
    (kafka_topic= 'shipments', value_format='json', timestamp='shipment_time');

EOF

SECONDS=0
log "START BENCHMARK for QUERY 0"
kubectl exec -i ksql-0 -- bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/localhost:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://localhost:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM FILTERED_STREAM AS SELECT
  *
FROM
  ORDERS
WHERE order_category='truck';
EOF

wait_for_stream_to_finish "FILTERED_STREAM"
throughtput "FILTERED_STREAM" "$SECONDS"

log "Verify we have received data in topic FILTERED_STREAM"
playground topic consume --topic FILTERED_STREAM --expected-messages 1

SECONDS=0
log "START BENCHMARK for QUERY 1"
kubectl exec -i ksql-0 -- bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/localhost:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://localhost:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM ENRICHED_O_C AS SELECT
  UNIX_TIMESTAMP() JOINTIME,
  O.ORDERTIME ORDERTIME,
  O.ORDERID ORDERID,
  O.PRODUCTID PRODUCTID,
  O.ORDERUNITS ORDERUNITS,
  O.CUSTOMERID CUSTOMERID,
  CUSTOMERS.FIRSTNAME FIRSTNAME,
  CUSTOMERS.LASTNAME LASTNAME,
  CUSTOMERS.GENDER GENDER,
  CUSTOMERS.RANDOM_DATA RANDOM_DATA,
  CUSTOMERS.ADDRESS ADDRESS
FROM
  ORDERS O
LEFT OUTER JOIN
    CUSTOMERS CUSTOMERS
    ON ((O.CUSTOMERID = CUSTOMERS.CUSTOMERID));
EOF

wait_for_stream_to_finish "ENRICHED_O_C"
throughtput "ENRICHED_O_C" "$SECONDS"

log "Verify we have received data in topic ENRICHED_O_C"
playground topic consume --topic ENRICHED_O_C --expected-messages 1

SECONDS=0
log "START BENCHMARK for QUERY 2"
kubectl exec -i ksql-0 -- bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/localhost:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://localhost:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM ENRICHED_O_C_P AS SELECT
  UNIX_TIMESTAMP() JOINTIME,
  ORDERTIME,
  ORDERID,
  P.PRODUCTID as PRODUCTID,
  ORDERUNITS,
  CUSTOMERID,
  FIRSTNAME,
  LASTNAME,
  GENDER,
  RANDOM_DATA,
  ADDRESS,
  NAME as ProductName,
  category,
  description
FROM
  ENRICHED_O_C o
LEFT JOIN
  PRODUCTS p
ON O.PRODUCTID = P.PRODUCTID;
EOF

wait_for_stream_to_finish "ENRICHED_O_C_P"
throughtput "ENRICHED_O_C_P" "$SECONDS"

log "Verify we have received data in topic ENRICHED_O_C_P"
playground topic consume --topic ENRICHED_O_C_P --expected-messages 1

SECONDS=0
log "START BENCHMARK for QUERY 3"
kubectl exec -i ksql-0 -- bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/localhost:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://localhost:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM ORDERS_SHIPPED AS SELECT
  UNIX_TIMESTAMP() JOINTIME,
  O.ORDERID O_ORDERID,
  S.ORDERID S_ORDERID,
  S.SHIPMENTID SHIPMENTID,
  O.PRODUCTID PRODUCTID,
  O.CUSTOMERID CUSTOMERID,
  O.ORDERUNITS ORDERUNITS,
  PRODUCTNAME,
  CATEGORY,
  DESCRIPTION,
  FIRSTNAME,
  lastname,
  gender,
  RANDOM_DATA,
  address
FROM
  ENRICHED_O_C_P o
INNER JOIN SHIPMENTS S
  WITHIN 2 HOURS
ON O.ORDERID = S.ORDERID;
EOF

wait_for_stream_to_finish "ORDERS_SHIPPED"
throughtput "ORDERS_SHIPPED" "$SECONDS"

log "Verify we have received data in topic ORDERS_SHIPPED"
playground topic consume --topic ORDERS_SHIPPED --expected-messages 1

SECONDS=0
log "START BENCHMARK for QUERY 4"
kubectl exec -i ksql-0 -- bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/localhost:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://localhost:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE TABLE ORDERPER_PROD_CUST_AGG AS SELECT
  os.PRODUCTID PRODUCTID,
  os.CUSTOMERID CUSTOMERID,
  COUNT(*) COUNTVAL,
  SUM(os.ORDERUNITS) ORDERSUM,
  MIN(UNIX_TIMESTAMP()) MINTIME,
  MAX(UNIX_TIMESTAMP()) MAXTIME,
  MAX(UNIX_TIMESTAMP()) - MIN(UNIX_TIMESTAMP()) TIMEDIFF
FROM
  ORDERS_SHIPPED os
WINDOW TUMBLING ( SIZE 1 MINUTES )
GROUP BY
  os.PRODUCTID, os.CUSTOMERID;
EOF

wait_for_stream_to_finish "ORDERPER_PROD_CUST_AGG"
throughtput "ORDERPER_PROD_CUST_AGG" "$SECONDS"

log "Verify we have received data in topic ORDERPER_PROD_CUST_AGG"
playground topic consume --topic ORDERPER_PROD_CUST_AGG --expected-messages 1