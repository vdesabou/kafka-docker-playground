#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
if [ "$PLAYGROUND_ENVIRONMENT" != "plaintext" ]
then
    logwarn "flink is only available in the plaintext environment"
    exit 111
fi

# the kafka sql connector is released for one flink minor version: pin both when FLINK_TAG is not set
if [ "$FLINK_TAG" == "latest" ]
then
    export FLINK_TAG="2.2"
fi
FLINK_KAFKA_CONNECTOR_VERSION=${FLINK_KAFKA_CONNECTOR_VERSION:-"5.0.0-2.2"}

# downloaded in /opt/flink/lib of the jobmanager, taskmanager and sql-client containers, instead of the interactive prompt of --enable-flink
export FLINK_URL="https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/${FLINK_KAFKA_CONNECTOR_VERSION}/flink-sql-connector-kafka-${FLINK_KAFKA_CONNECTOR_VERSION}.jar"
export ENABLE_FLINK=true

playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

playground topic create --topic orders
playground topic create --topic orders-enriched

log "Sending 10 orders to topic orders"
playground topic produce -t orders --nb-messages 10 << 'EOF'
{
  "type": "record",
  "name": "order",
  "fields": [
    {
      "name": "id",
      "type": {
        "type": "int",
        "arg.properties": {
          "iteration": { "start": 1 }
        }
      }
    },
    {
      "name": "product",
      "type": {
        "type": "string",
        "arg.properties": {
          "options": ["laptop", "phone", "tablet"]
        }
      }
    },
    {
      "name": "quantity",
      "type": {
        "type": "int",
        "arg.properties": {
          "range": { "min": 1, "max": 10 }
        }
      }
    }
  ]
}
EOF

log "Streaming job: copy orders to orders-enriched, with the product in upper case and a price"
playground flink sql << 'EOF'
CREATE TABLE orders (
  id INT,
  product STRING,
  quantity INT
) WITH (
  'connector' = 'kafka',
  'topic' = 'orders',
  'properties.bootstrap.servers' = 'broker:9092',
  'properties.group.id' = 'flink-orders',
  'scan.startup.mode' = 'earliest-offset',
  'format' = 'json'
);

CREATE TABLE orders_enriched (
  id INT,
  product STRING,
  quantity INT,
  price DOUBLE
) WITH (
  'connector' = 'kafka',
  'topic' = 'orders-enriched',
  'properties.bootstrap.servers' = 'broker:9092',
  'format' = 'json'
);

INSERT INTO orders_enriched
SELECT id, UPPER(product), quantity, quantity * 9.99 FROM orders;
EOF

log "Verify the 10 orders are in topic orders-enriched"
playground topic consume --topic orders-enriched --min-expected-messages 10 --timeout 120

log "Batch query: number of orders and total quantity (bounded read of topic orders)"
set +e
output=$(playground flink sql << 'EOF'
SET 'execution.runtime-mode' = 'batch';

CREATE TABLE orders (
  id INT,
  product STRING,
  quantity INT
) WITH (
  'connector' = 'kafka',
  'topic' = 'orders',
  'properties.bootstrap.servers' = 'broker:9092',
  'scan.startup.mode' = 'earliest-offset',
  'scan.bounded.mode' = 'latest-offset',
  'format' = 'json'
);

SELECT COUNT(*) AS nb_orders, SUM(quantity) AS total_quantity FROM orders;
EOF
)
ret=$?
set -e
echo "$output"
if [ $ret -ne 0 ] || ! echo "$output" | grep -q -E "^\| +10 \|"
then
    logerror "❌ the batch query did not count 10 orders"
    exit 1
fi

log "The streaming job is still running"
playground flink list-jobs --state RUNNING

log "Cancel it"
playground flink cancel --all
