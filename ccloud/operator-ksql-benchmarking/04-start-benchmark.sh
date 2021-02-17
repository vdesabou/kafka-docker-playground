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

set +e
# https://rmoff.net/2019/03/25/terminate-all-ksql-queries/
log "TERMINATE all queries, if applicable"
kubectl exec -i connectors-0 -- bash -c "curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
         -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
         -d '{\"ksql\": \"SHOW QUERIES;\"}' | \
  jq '.[].queries[].id' | \
  xargs -Ifoo curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
           -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
           -d '{\"ksql\": \"TERMINATE 'foo';\"}'"
log "DROP all streams, if applicable"
kubectl exec -i connectors-0 -- bash -c "curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
           -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
           -d '{\"ksql\": \"SHOW STREAMS;\"}' | \
    jq '.[].streams[].name' | \
    xargs -Ifoo curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
             -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
             -d '{\"ksql\": \"DROP STREAM 'foo';\"}'"
log "DROP all tables, if applicable"
kubectl exec -i connectors-0 -- bash -c "curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
             -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
             -d '{\"ksql\": \"SHOW TABLES;\"}' | \
      jq '.[].tables[].name' | \
      xargs -Ifoo curl -s -X \"POST\" \"http://ksql:9088/ksql\" \
               -H \"Content-Type: application/vnd.ksql.v1+json; charset=utf-8\" \
               -d '{\"ksql\": \"DROP TABLE 'foo';\"}'"

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

wait_for_all_streams_to_finish "ENRICHED_O_C" "kubectl exec -i ksql-0 --"
throughput=$(echo $((orders_iterations / SECONDS)))
log "Took $SECONDS seconds. Throughput=$throughput msg/s"

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

wait_for_all_streams_to_finish "ENRICHED_O_C_P" "kubectl exec -i ksql-0 --"
throughput=$(echo $((orders_iterations / SECONDS)))
log "Took $SECONDS seconds. Throughput=$throughput msg/s"

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

wait_for_all_streams_to_finish "ORDERS_SHIPPED" "kubectl exec -i ksql-0 --"
throughput=$(echo $((orders_iterations / SECONDS)))
log "Took $SECONDS seconds. Throughput=$throughput msg/s"

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

wait_for_all_streams_to_finish "ORDERPER_PROD_CUST_AGG" "kubectl exec -i ksql-0 --"
throughput=$(echo $((orders_iterations / SECONDS)))
log "Took $SECONDS seconds. Throughput=$throughput msg/s"