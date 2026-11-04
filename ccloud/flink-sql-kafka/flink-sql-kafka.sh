#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

bootstrap_ccloud_environment

# compute pool in the environment and region of the cluster: an existing one, or kdp-flink-<cloud>-<region>
bootstrap_ccloud_flink_compute_pool

function cleanup_cloud_resources {
    set +e
    log "Deleting the Flink statements created by playground flink sql"
    playground flink cancel --environment ccloud --all --delete
    if [ -n "$GITHUB_RUN_NUMBER" ]
    then
        # the secrets store of the CI runner does not survive the job: the key would be lost
        delete_ccloud_flink_api_key
    fi
    set -e
}
trap cleanup_cloud_resources EXIT

set +e
playground topic delete --topic flink_orders
playground topic delete --topic flink_orders_enriched
sleep 3
set -e
playground topic create --topic flink_orders --nb-partitions 1

log "Sending 10 Avro orders to topic flink_orders: with its schema, the topic is a Flink table already"
playground topic produce -t flink_orders --nb-messages 10 --value-format avro << 'EOF'
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

log "Streaming statement: copy flink_orders to flink_orders_enriched, with the product in upper case and a price"
playground flink sql --environment ccloud << 'EOF'
CREATE TABLE IF NOT EXISTS flink_orders_enriched (
  id INT,
  product STRING,
  quantity INT,
  price DOUBLE
) DISTRIBUTED INTO 1 BUCKETS;

INSERT INTO flink_orders_enriched
SELECT id, UPPER(product), quantity, quantity * 9.99 FROM flink_orders;
EOF

log "Verify the 10 orders are in topic flink_orders_enriched"
playground topic consume --topic flink_orders_enriched --min-expected-messages 10 --timeout 180

log "Query: number of orders and total quantity (bounded read of topic flink_orders)"
set +e
output=$(playground flink sql --environment ccloud << 'EOF'
SELECT COUNT(*) AS nb_orders, SUM(quantity) AS total_quantity
FROM flink_orders /*+ OPTIONS('scan.bounded.mode' = 'latest-offset') */;
EOF
)
ret=$?
set -e
echo "$output"
if [ $ret -ne 0 ] || ! echo "$output" | grep -q -E "^\| +10 \|"
then
    logerror "❌ the query did not count 10 orders"
    exit 1
fi

log "The streaming statement is still running"
playground flink list-jobs --environment ccloud --state RUNNING

log "Stop it"
playground flink cancel --environment ccloud --all
