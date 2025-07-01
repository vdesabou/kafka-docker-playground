#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

playground topic create -t control-iceberg 

log "Sending messages to topic payments"
playground topic produce -t payments --nb-messages $(wc -l <"../../connect/connect-iceberg-sink/data/transactions.json") --value ../../connect/connect-iceberg-sink/data/transactions.json

log "Creating Iceberg sink connector"
playground connector create-or-update --connector iceberg-sink  << EOF
{
  "tasks.max": "1",
  "topics": "payments",
  "connector.class": "io.tabular.iceberg.connect.IcebergSinkConnector",
  "iceberg.catalog.s3.endpoint": "http://minio:9000",
  "iceberg.catalog.s3.secret-access-key": "minioadmin",
  "iceberg.catalog.s3.access-key-id": "minioadmin",
  "iceberg.catalog.s3.path-style-access": "true",
  "iceberg.catalog.uri": "http://rest:8181",
  "iceberg.catalog.warehouse": "s3://warehouse/",
  "iceberg.catalog.client.region": "eu-west-1",
  "iceberg.catalog.type": "rest",
  "iceberg.control.commit.interval-ms": "1000",
  "iceberg.tables.auto-create-enabled": "true",
  "iceberg.tables": "orders.payments",
  "value.converter.schemas.enable": "false",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "schemas.enable": "false"
}
EOF

sleep 30

playground connector show-lag --max-wait 300

if [ -z "$GITHUB_RUN_NUMBER" ]
then
  # doesn't work on github actions
  # not running with github actions
  log "You can open the jupyter lab at http://localhost:8888/lab/tree/notebooks and use the sample notebook in notebooks/iceberg.ipynb to query the table"

  log "Verify data is in Iceberg"
  docker exec -i spark-iceberg spark-sql << EOF
SELECT *
FROM orders.payments
LIMIT 10;
EOF
fi